"""SQLAlchemy/FastAPI compatibility adapter; original operations are untouched."""
from .legacy import identity as implementation

class IdentityAdapter:
    login = staticmethod(implementation.login)
    current_account = staticmethod(implementation.current_account)
