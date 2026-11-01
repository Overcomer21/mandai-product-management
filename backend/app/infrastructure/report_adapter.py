"""SQLAlchemy/FastAPI compatibility adapter; original operations are untouched."""
from .legacy import report as implementation

class ReportAdapter:
    test_report = staticmethod(implementation.test_report)
