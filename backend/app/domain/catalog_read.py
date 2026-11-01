"""Framework-free catalog read contracts and snapshot data."""
from dataclasses import dataclass
from decimal import Decimal
from typing import Protocol

@dataclass(frozen=True)
class CatalogFilter:
    category: str | None = None
    search: str | None = None
    in_stock: bool = False

@dataclass(frozen=True)
class ProductSnapshot:
    id: int
    name: str
    description: str
    category: str
    price: Decimal
    stock: int
    is_active: bool
    image_url: str
    spin_image_urls: str

class CatalogReadRepository(Protocol):
    def categories(self) -> list[str]: ...
    def count(self, criteria: CatalogFilter) -> int: ...
    def page(self, criteria: CatalogFilter, limit: int, offset: int, sort: str) -> list[ProductSnapshot]: ...
    def detail(self, product_id: int) -> ProductSnapshot | None: ...
