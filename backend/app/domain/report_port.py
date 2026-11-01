"""Feature-specific application boundary: no framework/database imports."""
from typing import Protocol, Any

class ReportPort(Protocol):
    def test_report(self, **kwargs: Any) -> Any: ...
