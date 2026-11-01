"""Use-case entry points bound to a feature-specific port.
Business and SQL logic is preserved in the compatibility adapter.
"""
from ..domain.identity_port import IdentityPort

class IdentityService:
    def __init__(self, port: IdentityPort) -> None:
        self._port = port

    def login(self, **kwargs):
        return self._port.login(**kwargs)

    def current_account(self, **kwargs):
        return self._port.current_account(**kwargs)

