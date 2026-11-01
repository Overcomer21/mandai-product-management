"""SQLAlchemy/FastAPI compatibility adapter; original operations are untouched."""
from .legacy import orders as implementation

class OrdersAdapter:
    buy = staticmethod(implementation.buy)
    my_orders = staticmethod(implementation.my_orders)
    checkout = staticmethod(implementation.checkout)
    order_details = staticmethod(implementation.order_details)
