"""SQLAlchemy/FastAPI compatibility adapter; original operations are untouched."""
from .legacy import catalog as implementation

class CatalogAdapter:
    catalog_categories = staticmethod(implementation.catalog_categories)
    catalog_count = staticmethod(implementation.catalog_count)
    catalog = staticmethod(implementation.catalog)
    product_detail = staticmethod(implementation.product_detail)
    admin_products_count = staticmethod(implementation.admin_products_count)
    admin_products_categories = staticmethod(implementation.admin_products_categories)
    admin_products_stats = staticmethod(implementation.admin_products_stats)
    admin_list = staticmethod(implementation.admin_list)
    admin_detail = staticmethod(implementation.admin_detail)
    create_product = staticmethod(implementation.create_product)
    edit_product = staticmethod(implementation.edit_product)
    delete_product = staticmethod(implementation.delete_product)
