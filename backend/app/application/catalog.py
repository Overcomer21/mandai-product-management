"""Use-case entry points bound to a feature-specific port.
Business and SQL logic is preserved in the compatibility adapter.
"""
from ..domain.catalog_port import CatalogPort

class CatalogService:
    def __init__(self, port: CatalogPort) -> None:
        self._port = port

    def catalog_categories(self, **kwargs):
        return self._port.catalog_categories(**kwargs)

    def catalog_count(self, **kwargs):
        return self._port.catalog_count(**kwargs)

    def catalog(self, **kwargs):
        return self._port.catalog(**kwargs)

    def product_detail(self, **kwargs):
        return self._port.product_detail(**kwargs)

    def admin_products_count(self, **kwargs):
        return self._port.admin_products_count(**kwargs)

    def admin_products_categories(self, **kwargs):
        return self._port.admin_products_categories(**kwargs)

    def admin_products_stats(self, **kwargs):
        return self._port.admin_products_stats(**kwargs)

    def admin_list(self, **kwargs):
        return self._port.admin_list(**kwargs)

    def admin_detail(self, **kwargs):
        return self._port.admin_detail(**kwargs)

    def create_product(self, **kwargs):
        return self._port.create_product(**kwargs)

    def edit_product(self, **kwargs):
        return self._port.edit_product(**kwargs)

    def delete_product(self, **kwargs):
        return self._port.delete_product(**kwargs)

