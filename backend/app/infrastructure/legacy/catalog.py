import hashlib
import json
import logging
import os
import uuid
from decimal import Decimal
from fastapi import FastAPI, APIRouter, Depends, HTTPException, Header, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, update, delete, exists, text, or_, func, case
from sqlalchemy.exc import IntegrityError, OperationalError, SQLAlchemyError
from sqlalchemy.orm import Session, selectinload
from ...database import get_db
from ...models import User, Product, Order, OrderItem, Payment
from ...schemas import ProductInput, ProductOut, Login, PurchaseInput, PurchaseOut, CheckoutInput
from ...security import current_user, admin_only, verify_password, issue_token
from ...login_guard import login_guard
logger = logging.getLogger(__name__)
DELIVERY_FEE = Decimal('4.90')


def catalog_categories(db: Session = Depends(get_db)):
    return list(db.scalars(select(Product.category).where(Product.is_active == True)
                           .distinct().order_by(Product.category)).all())

def _filtered_catalog_statement(category: str | None, search: str | None, in_stock: bool):
    """Single source of truth for customer catalogue and count filters."""
    stmt = select(Product).where(Product.is_active == True)
    if category and category != 'All':
        stmt = stmt.where(Product.category == category)
    if search and search.strip():
        needle = search.strip().lower()
        # SQLAlchemy parameterizes LIKE expressions; escape wildcards for literal searches.
        needle = needle.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
        match = f'%{needle}%'
        stmt = stmt.where(or_(func.lower(Product.name).like(match, escape='\\'),
                              func.lower(Product.category).like(match, escape='\\'),
                              func.lower(Product.description).like(match, escape='\\')))
    if in_stock:
        stmt = stmt.where(Product.stock > 0)
    return stmt

def catalog_count(
    db: Session = Depends(get_db),
    category: str | None = Query(default=None, max_length=100),
    search: str | None = Query(default=None, max_length=160),
    in_stock: bool = Query(default=False),
):
    stmt = _filtered_catalog_statement(category, search, in_stock)
    count_stmt = select(func.count()).select_from(stmt.order_by(None).subquery())
    return {'total': db.scalar(count_stmt) or 0}

def catalog(
    db: Session = Depends(get_db),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    category: str | None = Query(default=None, max_length=100),
    search: str | None = Query(default=None, max_length=160),
    in_stock: bool = Query(default=False),
    sort: str = Query(default='Default', pattern='^(Default|Name|Price low|Price high)$'),
):
    stmt = _filtered_catalog_statement(category, search, in_stock)
    if sort == 'Name':
        stmt = stmt.order_by(Product.name, Product.id)
    elif sort == 'Price low':
        stmt = stmt.order_by(Product.price.asc(), Product.id)
    elif sort == 'Price high':
        stmt = stmt.order_by(Product.price.desc(), Product.id)
    else:
        stmt = stmt.order_by(Product.id)
    rows = db.scalars(stmt.offset(offset).limit(limit)).all()
    return [ProductOut.model_validate(p, from_attributes=True) for p in rows]

def product_detail(product_id:int,db:Session=Depends(get_db)):
    product=db.get(Product,product_id)
    if not product or not product.is_active:raise HTTPException(404,'Product not found')
    return product

def _admin_product_statement(category: str | None, search: str | None, in_stock: bool):
    # Admin inventory includes inactive products; customer catalogue does not.
    stmt = select(Product)
    if category and category != 'All':
        stmt = stmt.where(Product.category == category)
    if search and search.strip():
        needle = search.strip().lower().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
        match = f'%{needle}%'
        stmt = stmt.where(or_(func.lower(Product.name).like(match, escape='\\'),
                              func.lower(Product.category).like(match, escape='\\'),
                              func.lower(Product.description).like(match, escape='\\')))
    if in_stock:
        stmt = stmt.where(Product.stock > 0)
    return stmt

def admin_products_count(
    db: Session = Depends(get_db), _admin: User = Depends(admin_only),
    category: str | None = Query(default=None, max_length=100),
    search: str | None = Query(default=None, max_length=160),
    in_stock: bool = Query(default=False),
):
    stmt = _admin_product_statement(category, search, in_stock)
    return {'total': db.scalar(select(func.count()).select_from(stmt.order_by(None).subquery())) or 0}

def admin_products_categories(db: Session = Depends(get_db), _admin: User = Depends(admin_only)):
    return list(db.scalars(select(Product.category).distinct().order_by(Product.category)).all())

def admin_products_stats(db: Session = Depends(get_db), _admin: User = Depends(admin_only)):
    total, active, stock = db.execute(select(
        func.count(Product.id),
        func.sum(case((Product.is_active == True, 1), else_=0)),
        func.sum(Product.stock),
    )).one()
    return {'total': int(total or 0), 'active': int(active or 0), 'stock': int(stock or 0)}

def admin_list(
    db: Session = Depends(get_db), _admin: User = Depends(admin_only),
    limit: int | None = Query(default=None, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    category: str | None = Query(default=None, max_length=100),
    search: str | None = Query(default=None, max_length=160),
    in_stock: bool = Query(default=False),
    sort: str = Query(default='Default', pattern='^(Default|Name|Price low|Price high)$'),
):
    # Backwards-compatible: callers without limit still receive the full list.
    stmt = _admin_product_statement(category, search, in_stock)
    if sort == 'Name':
        stmt = stmt.order_by(Product.name, Product.id)
    elif sort == 'Price low':
        stmt = stmt.order_by(Product.price.asc(), Product.id)
    elif sort == 'Price high':
        stmt = stmt.order_by(Product.price.desc(), Product.id)
    else:
        stmt = stmt.order_by(Product.id)
    if limit is not None:
        stmt = stmt.offset(offset).limit(limit)
    return db.scalars(stmt).all()

def admin_detail(product_id:int,db:Session=Depends(get_db),_admin:User=Depends(admin_only)):
    product=db.get(Product,product_id)
    if not product:raise HTTPException(404,'Product not found')
    return product

def create_product(body:ProductInput,db:Session=Depends(get_db),_admin:User=Depends(admin_only)):
    product=Product(**body.model_dump())
    db.add(product);db.commit();db.refresh(product)
    return product

def edit_product(product_id:int,body:ProductInput,db:Session=Depends(get_db),_admin:User=Depends(admin_only)):
    product=db.get(Product,product_id)
    if not product:raise HTTPException(404,'Product not found')
    for key,val in body.model_dump().items():setattr(product,key,val)
    db.commit();db.refresh(product)
    return product

def delete_product(product_id: int, db: Session = Depends(get_db), _admin: User = Depends(admin_only)):
    # A SQL Core DELETE avoids ORM relationship cascade behavior. SQL Server
    # foreign keys must be enabled and configured NO ACTION to protect orders.
    try:
        result = db.execute(delete(Product).where(Product.id == product_id))
        if result.rowcount == 0:
            db.rollback()
            raise HTTPException(status_code=404, detail='Product not found')
        db.commit()
        return {'deleted': True, 'deactivated': False, 'action': 'deleted'}
    except IntegrityError as exc:
        db.rollback()
        logger.warning('DELETE product_id=%s rejected by database constraint', product_id, exc_info=True)
        # SQL Server error 547 is a foreign-key/reference constraint violation.
        original = getattr(exc, 'orig', None)
        diagnostics = ' '.join(str(item) for item in getattr(original, 'args', ()))
        if '547' in diagnostics:
            raise HTTPException(
                status_code=409,
                detail='Unable to delete product. This product has existing transactions or related records and cannot be deleted.',
            ) from exc
        raise HTTPException(
            status_code=409,
            detail='Unable to delete product because a database integrity constraint was violated.',
        ) from exc
    except HTTPException:
        raise
    except SQLAlchemyError as exc:
        db.rollback()
        logger.exception('DELETE product_id=%s failed during SQL execution', product_id)
        raise HTTPException(status_code=500, detail='Database error while deleting product.') from exc
