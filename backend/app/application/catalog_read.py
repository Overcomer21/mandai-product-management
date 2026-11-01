"""Framework-independent catalog read use cases; no HTTP or persistence imports."""
from ..domain.catalog_read import CatalogReadRepository, CatalogFilter, ProductSnapshot

class CatalogReadService:
    def __init__(self, repository: CatalogReadRepository) -> None:
        self._repository = repository

    def categories(self) -> list[str]:
        return self._repository.categories()

    def count(self, criteria: CatalogFilter) -> int:
        return self._repository.count(criteria)

    def page(self, criteria: CatalogFilter, limit: int, offset: int, sort: str) -> list[ProductSnapshot]:
        return self._repository.page(criteria, limit, offset, sort)

    def detail(self, product_id: int) -> ProductSnapshot | None:
        return self._repository.detail(product_id)
