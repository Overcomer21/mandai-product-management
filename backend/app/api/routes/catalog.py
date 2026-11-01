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
from ...database import get_db, SessionLocal
from ...models import User, Product, Order, OrderItem, Payment
from ...schemas import ProductInput, ProductOut, Login, PurchaseInput, PurchaseOut, CheckoutInput
from ...security import current_user, admin_only, verify_password, issue_token
from ...login_guard import login_guard
logger = logging.getLogger(__name__)
DELIVERY_FEE = Decimal('4.90')
from ...application.catalog import CatalogService
from ...infrastructure.catalog_adapter import CatalogAdapter
service = CatalogService(CatalogAdapter())
from ...domain.catalog_read import CatalogFilter
from ...application.catalog_read import CatalogReadService
from ...infrastructure.catalog_read_sqlalchemy import SqlAlchemyCatalogReadRepository

def _read_service(db: Session) -> CatalogReadService:
    return CatalogReadService(SqlAlchemyCatalogReadRepository(db))
router_segment_2 = APIRouter()



@router_segment_2.get('/api/products/categories', response_model=list[str])
def catalog_categories(db: Session=Depends(get_db)):
    return _read_service(db).categories()

@router_segment_2.get('/api/products/count')
def catalog_count(db: Session=Depends(get_db), category: str | None=Query(default=None, max_length=100), search: str | None=Query(default=None, max_length=160), in_stock: bool=Query(default=False)):
    return {'total': _read_service(db).count(CatalogFilter(category, search, in_stock))}

@router_segment_2.get('/api/products', response_model=list[ProductOut])
def catalog(limit: int=Query(default=20, ge=1, le=100), offset: int=Query(default=0, ge=0), category: str | None=Query(default=None, max_length=100), search: str | None=Query(default=None, max_length=160), in_stock: bool=Query(default=False), sort: str=Query(default='Default', pattern='^(Default|Name|Price low|Price high)$')):
    # Keep the database session scoped to the read operation only.
    # page() returns detached ProductSnapshot values; no ORM access is needed afterward.
    with SessionLocal() as db:
        products = _read_service(db).page(CatalogFilter(category, search, in_stock), limit, offset, sort)
    return [ProductOut.model_validate(vars(product)) for product in products]

@router_segment_2.get('/api/products/{product_id}', response_model=ProductOut)
def product_detail(product_id: int, db: Session=Depends(get_db)):
    product = _read_service(db).detail(product_id)
    if product is None:
        raise HTTPException(404, 'Product not found')
    return ProductOut.model_validate(vars(product))

@router_segment_2.get('/api/admin/products/count')
def admin_products_count(db: Session=Depends(get_db), _admin: User=Depends(admin_only), category: str | None=Query(default=None, max_length=100), search: str | None=Query(default=None, max_length=160), in_stock: bool=Query(default=False)):
    return service.admin_products_count(db=db, _admin=_admin, category=category, search=search, in_stock=in_stock)

@router_segment_2.get('/api/admin/products/categories', response_model=list[str])
def admin_products_categories(db: Session=Depends(get_db), _admin: User=Depends(admin_only)):
    return service.admin_products_categories(db=db, _admin=_admin)

@router_segment_2.get('/api/admin/products/stats')
def admin_products_stats(db: Session=Depends(get_db), _admin: User=Depends(admin_only)):
    return service.admin_products_stats(db=db, _admin=_admin)

@router_segment_2.get('/api/admin/products', response_model=list[ProductOut])
def admin_list(db: Session=Depends(get_db), _admin: User=Depends(admin_only), limit: int | None=Query(default=None, ge=1, le=100), offset: int=Query(default=0, ge=0), category: str | None=Query(default=None, max_length=100), search: str | None=Query(default=None, max_length=160), in_stock: bool=Query(default=False), sort: str=Query(default='Default', pattern='^(Default|Name|Price low|Price high)$')):
    return service.admin_list(db=db, _admin=_admin, limit=limit, offset=offset, category=category, search=search, in_stock=in_stock, sort=sort)

@router_segment_2.get('/api/admin/products/{product_id}', response_model=ProductOut)
def admin_detail(product_id: int, db: Session=Depends(get_db), _admin: User=Depends(admin_only)):
    return service.admin_detail(product_id=product_id, db=db, _admin=_admin)

@router_segment_2.post('/api/admin/products', response_model=ProductOut, status_code=201)
def create_product(body: ProductInput, db: Session=Depends(get_db), _admin: User=Depends(admin_only)):
    return service.create_product(body=body, db=db, _admin=_admin)

@router_segment_2.put('/api/admin/products/{product_id}', response_model=ProductOut)
def edit_product(product_id: int, body: ProductInput, db: Session=Depends(get_db), _admin: User=Depends(admin_only)):
    return service.edit_product(product_id=product_id, body=body, db=db, _admin=_admin)

@router_segment_2.delete('/api/admin/products/{product_id}')
def delete_product(product_id: int, db: Session=Depends(get_db), _admin: User=Depends(admin_only)):
    return service.delete_product(product_id=product_id, db=db, _admin=_admin)

