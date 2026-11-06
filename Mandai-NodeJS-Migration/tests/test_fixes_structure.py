
"""Read-only structural regression checks for F01/F03/F05/F06.

Run from Mandai-NodeJS-Migration:

    python -m unittest discover -s tests -p "test_fixes_structure.py" -v

These tests do not modify application code, SQL Server, Redis or GitHub.
They do not replace Flutter compile/widget tests or live integration tests.
"""

from pathlib import Path
import re
import unittest


# Node.js project root:
# C:\UIPath\mandai-product-management_nodejs\Mandai-NodeJS-Migration
BACKEND_ROOT = Path(__file__).resolve().parents[1]

# Flutter project source root:
# C:\UIPath\mandai-product-management_nodejs\frontend\lib
FLUTTER_ROOT = BACKEND_ROOT.parent / "frontend" / "lib"


def read_backend(path: str) -> str:
    """Read a Node.js backend/configuration source file."""
    file_path = BACKEND_ROOT / path

    if not file_path.is_file():
        raise FileNotFoundError(
            f"Backend file not found: {file_path}"
        )

    return file_path.read_text(encoding="utf-8")


def read_flutter(path: str) -> str:
    """Read a Flutter Dart source file."""
    file_path = FLUTTER_ROOT / path

    if not file_path.is_file():
        raise FileNotFoundError(
            f"Flutter file not found: {file_path}"
        )

    return file_path.read_text(encoding="utf-8")


class TargetedStructureTests(unittest.TestCase):

    def test_f01_catalog_writer_redis_shared(self):
        """F01: Catalog readers and writers share Redis."""

        compose = read_backend("deploy/docker-compose.yml")

        services = (
            "catalog1",
            "catalog2",
            "catalog3",
            "catalog4",
            "commerce1",
            "commerce2",
            "admin",
        )

        for service in services:
            with self.subTest(service=service):
                pattern = (
                    rf"(?m)^  {re.escape(service)}:\s*\n"
                    rf"(?:(?!^  \w).|\n)*?"
                    rf"REDIS_URL:\s*redis://redis:6379"
                )

                self.assertRegex(
                    compose,
                    pattern,
                    f"{service} must use shared Redis",
                )

        identity_pattern = (
            r"(?m)^  identity:\s*\n"
            r"(?:(?!^  \w).|\n)*?"
            r"LOGIN_GUARD_REDIS_URL:\s*redis://redis:6379"
        )

        self.assertRegex(compose, identity_pattern)

    def test_f03_identity_guards(self):
        """F03: Identity service requires Redis login guard."""

        server = read_backend("src/server.js")
        guard = read_backend("src/infrastructure/login-guard.js")

        self.assertIn("mode==='identity'", server)

        self.assertIn(
            "throw new Error('Identity service requires",
            server,
        )

        required_limits = (
            "ACCOUNT_IP_LIMIT = 5",
            "IP_LIMIT = 30",
            "ACCOUNT_LIMIT = 15",
            "WINDOW_SECONDS = 900",
        )

        for item in required_limits:
            with self.subTest(limit=item):
                self.assertIn(item, guard)

        self.assertIn("redis.call('EXPIRE'", guard)

    def test_f05_widget_parts_declared_and_exist(self):
        """F05: Flutter widget parts are declared and exist."""

        source = read_flutter("widgets/store_widgets.dart")

        part_names = re.findall(
            r"(?m)^part '([^']+)';",
            source,
        )

        self.assertEqual(
            len(part_names),
            4,
            "Expected four Dart part declarations",
        )

        self.assertEqual(
            len(set(part_names)),
            4,
            "Duplicate Dart part declarations found",
        )

        for relative in part_names:
            with self.subTest(part=relative):
                file_path = (
                    FLUTTER_ROOT / "widgets" / relative
                )

                self.assertTrue(
                    file_path.is_file(),
                    f"Missing Dart part: {file_path}",
                )

                content = file_path.read_text(
                    encoding="utf-8",
                )

                self.assertIn(
                    "part of '../store_widgets.dart';",
                    content,
                )

        self.assertIn("class MainMasterLayout", source)
        self.assertIn("class StoreTopPanel", source)

    def test_f06_delete_not_deactivate(self):
        """F06: Product deletion terminology matches HTTP DELETE."""

        repository = read_flutter(
            "features/products/data/product_repository.dart"
        )

        bloc = read_flutter(
            "features/products/bloc/product_bloc.dart"
        )

        card = read_flutter(
            "features/products/view/product_card.dart"
        )

        # The original test refers to app/shell.dart.
        # The uploaded project review also identified core/shell.dart.
        # Prefer the existing file without modifying either.
        shell_candidates = (
            "app/shell.dart",
            "core/shell.dart",
        )

        shell_path = next(
            (
                path
                for path in shell_candidates
                if (FLUTTER_ROOT / path).is_file()
            ),
            None,
        )

        self.assertIsNotNone(
            shell_path,
            "Cannot locate Flutter shell: "
            "expected app/shell.dart or core/shell.dart",
        )

        shell = read_flutter(shell_path)

        self.assertRegex(
            repository,
            r"Future<void>\s+delete\(int id\)",
        )

        self.assertIn(
            "'DELETE', '/api/admin/products/$id'",
            repository,
        )

        self.assertIn("ProductDeleted", bloc)
        self.assertIn("Product deleted", bloc)

        self.assertIn("Delete product", card)
        self.assertIn("Delete product?", shell)
        self.assertIn("ProductDeleted(product.id)", shell)

        for name, content in (
            ("product_repository.dart", repository),
            ("product_bloc.dart", bloc),
            ("product_card.dart", card),
            (shell_path, shell),
        ):
            with self.subTest(file=name):
                self.assertNotRegex(
                    content,
                    r"(?i)deactivat",
                    f"Obsolete deactivate terminology in {name}",
                )


if __name__ == "__main__":
    unittest.main()
