# Mandai Wildlife Merchandise — Independent Coding Assessment

A full-stack merchandise management and customer storefront demo developed for Mandai Wildlife Group's coding assessment (Question 5).

> **Disclaimer:** This is an independent proof of concept, not an official Mandai Wildlife Group product. Sample content is for demonstration purposes. Stripe is integrated in **Test Mode**; no real card charges or transfers take place.

## Overview

The application provides a customer storefront, administrator inventory management, secure purchasing, and an optional Stripe sandbox checkout experience. It uses a shared Flutter frontend, a main FastAPI backend for transactional and administrative operations, and a separately runnable read-only Product Catalog FastAPI service. NGINX routes requests to the appropriate service, Redis provides shared catalog caching, and Microsoft SQL Server (`MandaiDB`) remains the single authoritative database.

### Technology stack

- **Frontend:** Flutter / Dart — Web, Windows, Android, iOS, macOS and Linux targets (each requires platform-specific configuration and validation).
- **Backend:** Python / FastAPI REST/JSON APIs — main application and independently scalable read-only Product Catalog service.
- **Routing and load balancing:** NGINX (Docker), `least_conn` across four catalog instances.
- **Shared catalog cache:** Redis (cache, not the authoritative database).
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
- Git. Docker Desktop and Redis are required for the documented NGINX/Redis catalog scale-out configuration; the main API can be run independently for development. Android development requires the Android toolchain; iOS/macOS builds require macOS and Xcode.

## Local development

Run the commands from the repository root unless otherwise noted. Confirm the scripts and environment names in your checked-out source before running them.

### 1. Configure SQL Server

Use an existing SQL Server instance and the project's database setup/migration scripts as appropriate. Configure the backend to connect to **`MandaiDB`**. Ensure its login has only the necessary permissions.

**Important:** Do not rerun database creation, product seeding, or destructive cleanup against an existing `MandaiDB` containing data you need to preserve. Prefer an isolated test database for data-changing tests. The dedicated Q5 concurrency script is explicitly gated for `MandaiDB`; run it only with authorization and safeguards for disposable test records, and never modify existing master product data.

### 2. Start main FastAPI (PowerShell)

```powershell
cd C:\UIPath\mandai-product-management\backend
.\.venv\Scripts\Activate.ps1
# Install dependencies only when needed:
# python -m pip install -r requirements.txt
```

Create `backend/.env` from the provided example if present; configure the actual SQL Server connection, JWT secret, and any required demo-user credentials. Never commit `.env` or API keys.

```powershell
python -m uvicorn app.main:app --reload --port 8000
```

API documentation: http://localhost:8000/docs

### 3. Product Catalog microservices, Redis and NGINX (local scale-out)

The current scale-out configuration uses the dedicated FastAPI application entry point `app.product_catalog_main:app`, with four independently runnable instances on ports **8100–8103**. NGINX in Docker (`mandai-catalog-nginx-lb`) listens on container port **8080**, published on the tested Windows host at **52000**. Its canonical configuration is [`backend/catalog-nginx.conf`](backend/catalog-nginx.conf).

- Catalog reads (`/api/products` and applicable read-only catalog routes) are routed to the four catalog instances through the NGINX `catalog_backend` upstream using `least_conn`.
- Authentication, administrator product CRUD, purchases, checkout, orders, Stripe-related routes and `/media/` remain routed to the main FastAPI backend on **8000**. The NGINX `/media/` proxy forwards images to port 8000 and suppresses duplicate upstream CORS headers.
- Redis is shared by the catalog instances for catalog-response caching. **`MandaiDB` remains the source of truth**; Redis is not a second database for orders or inventory.
- The four catalog instances are separate FastAPI processes; this does **not** imply that each instance runs in its own Docker container. The observed local Docker deployment is for NGINX.

For the existing environment, first confirm Redis availability, active catalog processes and the running NGINX container before starting additional instances. The following commands are **read-only inspection**:

```powershell
cd C:\UIPath\mandai-product-management\backend
.\.venv\Scripts\Activate.ps1
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in @(8000,8100,8101,8102,8103,52000) } |
    Select-Object LocalAddress,LocalPort,OwningProcess
docker ps --filter "name=mandai-catalog-nginx-lb"
```

The local browser API base is `http://127.0.0.1:52000` when the catalog NGINX deployment is active. Use the Redis settings and startup procedures configured for the local environment. When recreating the NGINX container, mount or copy `backend/catalog-nginx.conf` to preserve the deployed configuration.

### 4. Start Flutter (PowerShell)

Open a second terminal from the repository root:

```powershell
cd frontend
flutter pub get
flutter run -d chrome --web-port 8085 --dart-define=API_BASE=http://127.0.0.1:52000
```

Run `flutter devices` to see which platforms are configured locally. **Do not run `flutter create .` over an existing configured project unless platform scaffolding is actually missing and existing files have been backed up.**

For an Android emulator using the local NGINX entry point, use `http://10.0.2.2:52000` if the emulator can reach that host port. Direct access to the main FastAPI backend uses `http://10.0.2.2:8000`. Physical mobile devices need a network-reachable API URL. Use HTTPS for deployed environments.

### 5. Stripe Test Mode

Configure the required Stripe **test** credentials and return/webhook settings using the project's environment configuration. Use Stripe test payment methods; no live funds are transferred. Production payment configuration and testing are covered under **Production readiness** below. Never commit Stripe secrets.

## Product Catalog Microservice — Verification Scope

This section covers the read-only Product Catalog microservice: NGINX (host port **52000**) distributes catalog requests across FastAPI instances (**8100–8103**). Each instance checks the shared Redis cache and accesses SQL Server (`MandaiDB`) on a cache miss. The main backend on port **8000** remains responsible for administrative writes, transactions and media.

The final Product Catalog microservice validation covers catalog GET responses and pagination, Redis shared caching, NGINX routing, and browser image/CORS handling in the local development environment. For production readiness, configuration adjustments and additional testing are required on the intended infrastructure and workloads.

## Main API routes

| Route | Purpose |
| --- | --- |
| `POST /api/auth/login` | Obtain an authentication token |
| `GET /api/products` | Read-only customer catalog through NGINX and Product Catalog service |
| `GET /api/products/{id}` | Retrieve one product through the registered catalog API route |
| `GET/POST/PUT/DELETE /api/admin/products` | Administrator product management; DELETE is a soft deactivation where implemented |
| `POST /api/purchases` | Authenticated purchase, with an `Idempotency-Key` header |
| `GET /api/orders/my` | Customer order history |

The main FastAPI backend continues to own administrator writes, purchase/checkout transactions and Stripe processing; the Product Catalog service is read-only. The project also includes optional Stripe Checkout, payment status, and return endpoints. Refer to the registered FastAPI routes and `/docs` for the exact paths and request schemas in the checked-out version.

## Security and design considerations

- JWT authentication and server-side role checks protect restricted API operations.
- NGINX CORS configuration permits the documented local Flutter Web origins and avoids duplicate CORS headers for proxied product images. CORS does not replace authentication or authorization.
- Purchase prices and available stock are checked on the server, not trusted from the client.
- SQL Server transactions and conditional inventory updates protect against race conditions and overselling.
- Relational constraints and soft deactivation support data integrity and historical transaction references.
- Production environment configuration and validation are described under **Production readiness** below.
- Flutter layouts aim to adapt to desktop and mobile screens; all platform-specific behavior still needs separate verification.

## Video Demo

- [Mandai Merchandise App Demo](VideoDemo/Mandai_Merchandise_App_Demo.mp4)
- [Mandai Merchandise App Lazy Loading Demo](VideoDemo/Mandai_Merchandise_App_LazyLoading.mp4)
- [Mandai Merchandise Mobile Lazy Loading Demo](VideoDemo/Mobile_Lazy_Loading.mp4)

## Documentation

- [`SPEC.md`](SPEC.md) — Original functional scope and acceptance criteria; unchanged.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — Current Product Catalog microservice architecture, NGINX routing, Redis cache, shared SQL Server and technical trade-offs.

**Assessment scope:** Independent demonstration project for Mandai Wildlife Group coding assessment.

## Production readiness

The Product Catalog Microservices architecture, including NGINX load balancing, Redis shared caching, service routing, and CORS configuration, has been implemented and validated in the local development environment.

For **production readiness**, environment-specific configuration adjustments and additional testing are required, including HTTPS, secrets management, CORS allowlists, cache consistency following administrator updates, Redis availability, service health and failover, SQL Server connection pools, shared media access, Stripe webhook handling, container lifecycle management, and performance testing under the intended production infrastructure and workloads.

Author: Yongky
