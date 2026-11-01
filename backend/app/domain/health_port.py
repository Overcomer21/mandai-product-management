"""Feature-specific application boundary: no framework/database imports."""
from typing import Protocol, Any

class HealthPort(Protocol):
    def health(self, **kwargs: Any) -> Any: ...
