"""Use-case entry points bound to a feature-specific port.
Business and SQL logic is preserved in the compatibility adapter.
"""
from ..domain.health_port import HealthPort

class HealthService:
    def __init__(self, port: HealthPort) -> None:
        self._port = port

    def health(self, **kwargs):
        return self._port.health(**kwargs)

