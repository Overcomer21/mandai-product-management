"""Use-case entry points bound to a feature-specific port.
Business and SQL logic is preserved in the compatibility adapter.
"""
from ..domain.orders_port import OrdersPort

class OrdersService:
    def __init__(self, port: OrdersPort) -> None:
        self._port = port

    def buy(self, **kwargs):
        return self._port.buy(**kwargs)

    def my_orders(self, **kwargs):
        return self._port.my_orders(**kwargs)

    def checkout(self, **kwargs):
        return self._port.checkout(**kwargs)

    def order_details(self, **kwargs):
        return self._port.order_details(**kwargs)

