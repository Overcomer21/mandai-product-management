"""SQLAlchemy/FastAPI compatibility adapter; original operations are untouched."""
from .legacy import health as implementation

class HealthAdapter:
    health = staticmethod(implementation.health)
