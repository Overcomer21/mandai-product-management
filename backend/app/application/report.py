"""Use-case entry points bound to a feature-specific port.
Business and SQL logic is preserved in the compatibility adapter.
"""
from ..domain.report_port import ReportPort

class ReportService:
    def __init__(self, port: ReportPort) -> None:
        self._port = port

    def test_report(self, **kwargs):
        return self._port.test_report(**kwargs)

