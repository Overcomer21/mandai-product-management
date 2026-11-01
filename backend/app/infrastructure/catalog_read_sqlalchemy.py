"""SQLAlchemy implementation of the domain catalog read port."""
from sqlalchemy import select, func, or_
from sqlalchemy.orm import Session
from ..models import Product
from ..domain.catalog_read import CatalogFilter, ProductSnapshot

class SqlAlchemyCatalogReadRepository:
    def __init__(self, session: Session):
        self._session = session

    @staticmethod
    def _snapshot(product: Product) -> ProductSnapshot:
        return ProductSnapshot(
            id=product.id, name=product.name, description=product.description,
            category=product.category, price=product.price, stock=product.stock,
            is_active=product.is_active, image_url=product.image_url,
            spin_image_urls=product.spin_image_urls,
        )

    @staticmethod
    def _statement(criteria: CatalogFilter):
        stmt = select(Product).where(Product.is_active == True)
        if criteria.category and criteria.category != 'All':
            stmt = stmt.where(Product.category == criteria.category)
        if criteria.search and criteria.search.strip():
            needle = criteria.search.strip().lower()
            needle = needle.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
            match = f'%{needle}%'
            stmt = stmt.where(or_(
                func.lower(Product.name).like(match, escape='\\'),
                func.lower(Product.category).like(match, escape='\\'),
                func.lower(Product.description).like(match, escape='\\'),
            ))
        if criteria.in_stock:
            stmt = stmt.where(Product.stock > 0)
        return stmt

    def categories(self) -> list[str]:
        return list(self._session.scalars(
            select(Product.category).where(Product.is_active == True)
            .distinct().order_by(Product.category)
        ).all())

    def count(self, criteria: CatalogFilter) -> int:
        stmt = self._statement(criteria)
        count_stmt = select(func.count()).select_from(stmt.order_by(None).subquery())
        return self._session.scalar(count_stmt) or 0

    def page(self, criteria: CatalogFilter, limit: int, offset: int, sort: str) -> list[ProductSnapshot]:
        stmt = self._statement(criteria)
        if sort == 'Name':
            stmt = stmt.order_by(Product.name, Product.id)
        elif sort == 'Price low':
            stmt = stmt.order_by(Product.price.asc(), Product.id)
        elif sort == 'Price high':
            stmt = stmt.order_by(Product.price.desc(), Product.id)
        else:
            stmt = stmt.order_by(Product.id)
        rows = self._session.scalars(stmt.offset(offset).limit(limit)).all()
        return [self._snapshot(product) for product in rows]

    def detail(self, product_id: int) -> ProductSnapshot | None:
        product = self._session.get(Product, product_id)
        if not product or not product.is_active:
            return None
        return self._snapshot(product)
