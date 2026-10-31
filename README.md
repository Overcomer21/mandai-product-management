# Mandai Wildlife Merchandise — Independent Coding Assessment

A full-stack merchandise management and customer storefront demo developed for Mandai Wildlife Group's coding assessment (Question 5).

> **Disclaimer:** This is an independent proof of concept, not an official Mandai Wildlife Group product. Sample content is for demonstration purposes. Stripe is integrated in **Test Mode**; no real card charges or transfers take place.

## Overview

The application provides a customer storefront, administrator inventory management, secure purchasing, and an optional Stripe sandbox checkout experience. It uses a shared Flutter codebase and a Python backend with Microsoft SQL Server as the source of truth for orders and inventory.

### Technology stack

- **Frontend:** Flutter / Dart — Web, Windows, Android, iOS, macOS and Linux targets (each requires platform-specific configuration and validation).
- **Backend:** Python / FastAPI with REST/JSON APIs.
- **Database:** Microsoft SQL Server (`MandaiDB`).
- **Authentication:** JWT access tokens and server-side Role-Based Access Control (RBAC).
- **Payment demo:** Stripe Checkout in Test Mode (sandbox).
- **Design:** Clean Architecture principles, modular/repository patterns, and selected Very Good Ventures (VGV) engineering practices, including BLoC in applicable modules.

## Main features

**Customers:** Browse and search the product catalog, filter by category and in-stock availability, sort products, view product media, manage a shopping cart, place purchases, and use the Stripe test checkout flow.

**Administrators:** Create, search, edit, and deactivate products; manage product inventory using authorized endpoints. Products referenced by historical orders are preserved rather than destructively removed.

**Transaction integrity:** Server-side validation, idempotency keys, database transactions, atomic conditional stock updates, commit/rollback behavior, and concurrency checks prevent overselling and inconsistent purchase records.

## Prerequisites

- Flutter SDK / Dart and a supported target platform toolchain (Chrome for Web; Visual Studio C++ workload for Windows desktop).
- Python and pip compatible with `backend/requirements.txt`.
- Microsoft SQL Server and Microsoft ODBC Driver 18 for SQL Server.
- SQL Server Management Studio (SSMS) or another SQL client.
- Git. Android development requires the Android toolchain; iOS/macOS builds require macOS and Xcode.

## Local development

Run the commands from the repository root unless otherwise noted. Confirm the scripts and environment names in your checked-out source before running them.

### 1. Configure SQL Server

Use an existing SQL Server instance and the project's database setup/migration scripts as appropriate. Configure the backend to connect to **`MandaiDB`**. Ensure its login has only the necessary permissions.

**Important:** Do not rerun database creation, product seeding, or destructive cleanup against an existing `MandaiDB` containing data you need to preserve. Prefer an isolated test database for data-changing tests. The dedicated Q5 concurrency script is explicitly gated for `MandaiDB`; run it only with authorization and safeguards for disposable test records, and never modify existing master product data.

### 2. Start FastAPI (PowerShell)

```powershell
cd backend
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Create `backend/.env` from the provided example if present; configure the actual SQL Server connection, JWT secret, and any required demo-user credentials. Never commit `.env` or API keys.

```powershell
python -m uvicorn app.main:app --reload --port 8000
```

API documentation: http://localhost:8000/docs

### 3. Start Flutter (PowerShell)

Open a second terminal from the repository root:

```powershell
cd frontend
flutter pub get
flutter run -d chrome --web-port 8080 --dart-define=API_BASE=http://localhost:8000
```

Run `flutter devices` to see which platforms are configured locally. **Do not run `flutter create .` over an existing configured project unless platform scaffolding is actually missing and existing files have been backed up.**

For an Android emulator, the backend running on the development computer is typically reachable through `http://10.0.2.2:8000` instead of `localhost`. Physical mobile devices need a network-reachable API URL. Use HTTPS for deployed environments.

### 4. Stripe Test Mode

Configure the required Stripe **test** credentials and return/webhook settings using the project's environment configuration. Use Stripe test payment methods; no live funds are transferred. Payment-session and webhook behavior must be validated before claiming production payment readiness. Never commit Stripe secrets.

## Testing

Typical checks, when the corresponding dependencies and test environment are configured:

```powershell
# Backend
cd backend
python -m pytest -q

# Frontend (in a separate command from frontend/)
cd ..\frontend
flutter analyze
flutter test
```

Additional SQL Server integration tests, concurrency checks, and read-only API stress tests are documented in the [Application Acceptance Test Results](APPLICATION_ACCEPTANCE_TEST_RESULTS.md). The dedicated SQL Server concurrency tests use disposable test records; do not alter retained master product data. Prefer an isolated database for general integration testing. The explicitly gated Q5 test below was run against `MandaiDB` and reported successful cleanup. Its cleanup status does not replace independent review of database changes.

### Comprehensive Concurrent Overselling Prevention Test

**PASS — No overselling observed in 1,000 concurrent purchase attempts.** The SQL Server test executed **100 concurrent buyers across 10 iterations**, with 30 units of test stock per iteration. Results: **300 successful purchases**, **700 expected out-of-stock rejections**, **zero reported errors**, and consistent inventory, order, and demo-payment records. All **10/10 iterations passed**, and the test reported successful cleanup. These results demonstrate effective overselling prevention under the tested concurrency conditions. Additional testing across different workloads, system configurations, and failure scenarios may be required to establish production readiness.

**Detailed results and evidence:** [Application Acceptance Test Results](APPLICATION_ACCEPTANCE_TEST_RESULTS.md) · [`q5-100-buyers-concurrency.json`](test-results/q5-100-buyers-concurrency.json).

Testing does not imply validation of every target device or production payment certification.

## Main API routes

| Route | Purpose |
| --- | --- |
| `POST /api/auth/login` | Obtain an authentication token |
| `GET /api/products` | Retrieve products |
| `GET /api/products/{id}` | Retrieve one product |
| `GET/POST/PUT/DELETE /api/admin/products` | Administrator product management; DELETE is a soft deactivation where implemented |
| `POST /api/purchases` | Authenticated purchase, with an `Idempotency-Key` header |
| `GET /api/orders/my` | Customer order history |

The project also includes optional Stripe Checkout, payment status, and return endpoints. Refer to the registered FastAPI routes and `/docs` for the exact paths and request schemas in the checked-out version.

## Security and design considerations

- JWT authentication and server-side role checks protect restricted API operations.
- CORS restricts allowed browser origins; it does not replace authentication or authorization.
- Purchase prices and available stock are checked on the server, not trusted from the client.
- SQL Server transactions and conditional inventory updates protect against race conditions and overselling.
- Relational constraints and soft deactivation support data integrity and historical transaction references.
- Use HTTPS, secret management, secure token storage, and validated Stripe webhooks before production deployment.
- Flutter layouts aim to adapt to desktop and mobile screens; all platform-specific behavior still needs separate verification.

## Documentation

- [`SPEC.md`](SPEC.md) — Scope, features, and assessment acceptance criteria.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — Architecture principles, database integrity, transactions, concurrency, security, payments, and technical trade-offs.
- [`APPLICATION_ACCEPTANCE_TEST_RESULTS.md`](APPLICATION_ACCEPTANCE_TEST_RESULTS.md) — AC01–AC08 acceptance criteria verification, automated test evidence, comprehensive 100-buyer concurrency testing, overselling prevention, and overall test results.

**Assessment scope:** This is a demonstration project; it is not an official product or a claim of production readiness.

## Author

Yongky
