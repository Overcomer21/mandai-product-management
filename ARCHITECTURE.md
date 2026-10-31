# Mandai Merchandise — Architecture

**Assessment:** Mandai Wildlife Group — Coding Assessment, Question 5

## 1. Architecture Overview

```text
Flutter / Dart UI (Storefront and Admin Dashboard)
                     |
                     | REST / JSON
                     v
             Python FastAPI
     Authentication | Products | Purchases
                     |
                     v
          SQL Server (MandaiDB)
                     |
             Orders / Inventory

        Stripe Test Mode (optional checkout flow)
```

The project uses a shared Flutter frontend, FastAPI backend, and SQL Server as the authoritative transaction and inventory database. Frontend code uses modular organization, repositories, and BLoC patterns in selected areas. The architecture description is scoped to the features and evidence reviewed.

## 2. Clean Architecture Principles and VGV Engineering Practices

The application follows **Clean Architecture principles** by promoting separation of concerns and organizing selected features around presentation, state management, and data access. The documented approach is pragmatic and modular; full layering across every screen requires a separate source-code audit.

Selected **Very Good Ventures (VGV) engineering practices** include:

- **BLoC-based state management:** Separates application state and business workflows from UI components in applicable features.
- **Repository pattern:** Organizes access to backend APIs and data behind reusable repositories.
- **Modular, maintainable code:** Encourages reusable components and clearer feature boundaries.
- **Automated testing and static analysis:** Helps validate behavior and improve code reliability.

## 3. Main Components

- **Presentation:** Customer catalog, shopping cart, and administrator dashboard.
- **API:** Authentication, product catalog, administrator CRUD, purchase, checkout, and order routes.
- **Authorization:** Authenticated endpoints and role checks for administrator-only functions.
- **Persistence:** SQL Server transactions for stock updates and order recording.
- **Payments:** Stripe Test Mode integration for demonstrating card-payment workflows.

## 4. Database Design and Referential Integrity

| Entity | Purpose |
| --- | --- |
| Users | Accounts and role assignments |
| Products | Catalog details, available stock, active status |
| Orders / Purchases | Purchase transactions, ownership and status |
| Order Items | Products, quantities and measured prices associated with an order |
| Payment Records | Payment/check-out status where applicable |

This is a logical summary, not an exhaustive physical table/column listing. `MandaiDB` remains the source of truth for actual schema names and constraints.

### Relational Data Integrity

Microsoft SQL Server is used as the relational database management system (RDBMS). Foreign key constraints, where defined in the physical `MandaiDB` schema, enforce referential integrity between related records (for example, orders, order items, and products). They help prevent orphaned records and reject deletes or updates that would violate those relationships.

Foreign key constraints work alongside transactional commits/rollbacks and controlled deletion policies, including soft deactivation of products referenced by documented sales, to preserve relational consistency and transaction history.

## 5. API Security: JWT, RBAC and CORS

- **JWT authentication:** After successful login, the API issues an access token. Protected endpoints validate the token before granting access.
- **Role-Based Access Control (RBAC):** Backend authorization checks restrict administrative operations to administrators and purchases to authorized customers.
- **CORS:** Cross-Origin Resource Sharing controls which web origins browsers may use to access the FastAPI API. Deployment should explicitly configure trusted frontend origins.
- **Secure operations:** The backend validates requests, prices, and stock; HTTPS is required for secure deployed communication.

CORS governs browser cross-origin access; JWT authentication and backend role checks provide separate security controls.

## 6. Transaction Management and Concurrency Control

1. Authenticate the customer and validate the purchase request.
2. Require an idempotency key to protect against duplicate retries.
3. Open a database transaction through the SQLAlchemy session (conceptually `BEGIN TRANSACTION`).
4. Perform an **atomic conditional stock update**, only when sufficient stock exists.
5. Verify affected rows, record the order, and `COMMIT` together as one atomic unit.
6. Reject insufficient-stock requests and `ROLLBACK` failed transactions, leaving inventory and order data consistent.

Concurrency tests exercised atomic stock updates and transaction handling. A verified test scenario of 20 competing purchase requests against stock of 10 resulted in 10 successful purchases and 10 rejected requests. Server-side validation of price and stock is part of the checkout implementation; broader production concurrency behavior requires representative testing.

## 7. Frontend Architecture: Responsive UI and Lazy Loading

- **Cross-platform approach:** Flutter/Dart supports shared frontend code across Web, Windows and Android in the demonstrated project workflow. Additional platform targets require platform-specific build and validation.
- **Responsive UI:** Layouts adapt to available screen space, including desktop side panels and mobile-friendly navigation.
- **Catalog loading:** The catalog API supports server-side pagination with `limit` and `offset` (configurable page size, maximum: 100). The Flutter catalog uses incremental/lazy loading and rendering to avoid loading the entire catalog at once.
- **Code organization:** Selected modules use feature-oriented structure, repositories, and BLoC for state management; the entire UI is not claimed to follow strict Clean Architecture.

## 8. Catalog Performance — Technical Approach

### Adaptive pagination — technical design

**Scope:** The customer-facing catalog combines responsive Flutter presentation with FastAPI and SQL Server offset-based pagination. Implementation details are documented alongside their relevant verification scope.

**Page-size selection and initial load**

- The adaptive frontend approach selects an initial catalog batch from **10, 15, 20, or 30 products** based on available viewport geometry and product-card dimensions. These are batch sizes, not the total number of catalog products.
- The initial storefront request starts at `offset=0`. The FastAPI catalog endpoint accepts `limit` (default 20, allowed 1–100) and `offset` (default 0, minimum 0), and applies `OFFSET`/`LIMIT` to the ordered SQL query.
- The catalog dataset reported for this assessment contains **2,022 product items**. Pagination allows incremental retrieval instead of transferring the complete catalog in the initial response.

**Incremental loading and state consistency**

1. The initial page populates the customer catalog and records the next offset.
2. When more items are needed, a subsequent request uses the current `limit` and next `offset`, then appends the returned records to the existing list.
3. A request-in-flight flag (`_catalogLoadingMore`) limits overlapping page fetches. A generation counter (`_catalogGeneration`) rejects stale results after a catalog refresh or filter change.
4. The frontend tracks whether further results are available (`_catalogHasMore`), and maintains a pagination error state (`_catalogPageError`) for handling request failures.
5. The adaptive pagination engineering approach includes deduplication by product ID when appending pages; final-build behavior is validated through source review and UI testing.

**Responsive presentation and rendering**

- Desktop layouts provide a persistent filter/sidebar area where screen width permits; mobile layouts expose filters through the existing Quick Access Panel/drawer.
- Incremental network loading and widget rendering are distinct optimizations. The catalog uses incremental network loading and grid rendering. Full viewport virtualization is a separate optimization that can be evaluated through Flutter profiling.
- Page-size choices are responsive design heuristics. Frame times, memory consumption, scroll stability, and behavior on Web/Windows/Android should be measured on the target devices and configurations.

**Pagination correctness and trade-offs**

- Filter, search, stock and sorting parameters belong to the **same backend query** as `limit` and `offset`; the SQL ordering is applied to the complete filtered result set before a page is returned.
- When a category, search term, stock filter or sort order changes, the desired flow resets the page offset and loads the first page of the new result set. Generation-based stale-response protection avoids displaying results from an obsolete request.
- Deterministic ordering uses `Product.id` as the default order or as a tie-breaker for name/price ordering. Offset pagination may shift if records are inserted or removed during browsing; product-ID deduplication reduces repeated display entries but is not a snapshot-isolation mechanism.
- The administrator catalog and customer catalog may use different loading paths. Customer-facing adaptive pagination is documented separately from administrator CRUD retrieval.

**Verification approach:** Confirm selected batch sizes, offsets, scroll-triggered requests, cancellation/stale-response behavior, filtering across page boundaries, retry handling, and UI frame times against the final application build. These checks complement the measured SQL and API load tests; they are separate from those performance measurements.

### Combined category filtering and sorting

- The API accepts optional `category`, `search`, and `in_stock` filters alongside `sort`, `limit`, and `offset`.
- Supported sort values are `Default`, `Name`, `Price low`, and `Price high`.
- The backend composes these conditions into a single SQL query, preserving the ordering of the complete filtered result set before pagination. Sorting only the currently loaded Flutter items would not correctly order the full catalog.
- At the API level, omitting the `category` parameter retrieves all active categories; specifying a category constrains the SQL query to matching products. The UI-to-API mapping for the `All` control should be confirmed through a captured request.

### SQL Server indexing

The following indexes are present on `dbo.Products` in `MandaiDB`:

| Index | Key columns | Intended access pattern |
| --- | --- | --- |
| `PK_Products` | `Id` | Primary-key access and default ordering |
| `IX_Products_Name_Id` | `Name, Id` | Name ordering with deterministic ID tie-break |
| `IX_Products_Price_Id` | `Price, Id` | Price ordering with deterministic ID tie-break |
| `IX_Products_IsActive_Category` | `IsActive, Category` | Filtering active products by category |

These are ordinary SQL Server indexes, not indexed views. Their actual use depends on the SQL Server query optimizer and query shape. The category index was added to support category selection without changing product master data.

### Combined-query SQL benchmark

A read-only SQL Server benchmark exercised **8 combinations** of category (`All`, `Apparel`) and sorting (`Default`, `Name`, `Price low`, `Price high`), **5 runs per combination** (40 executions total), using paginated queries in a catalog reported to contain **2,022 product items**. The measured average elapsed times ranged from **1.20 to 6.60 ms**; the maximum observed elapsed time was **18 ms**. The overall mean, calculated from eight equally weighted five-run scenario averages, was **2.83 ms** (rounded).

| Category | Default avg | Name avg | Price low avg | Price high avg |
| --- | ---: | ---: | ---: | ---: |
| All | 6.60 ms | 2.40 ms | 3.60 ms | 3.00 ms |
| Apparel | 1.20 ms | 2.20 ms | 1.80 ms | 1.80 ms |

The benchmark used a parameterized-style conditional filter, `CASE` expressions in `ORDER BY`, and `COUNT(*)` over a paginated subquery. **This is a synthetic SQL benchmark.** The actual SQLAlchemy-generated query, full-row retrieval, HTTP response time and Flutter rendering require separate measurements to establish end-to-end latency. Category filtering was observed to be responsive in the running application with the active-category index in place. This observation is qualitative; the SQL benchmark provides the recorded numeric measurements.

The measured SQL benchmark provides no demonstrated requirement for a SQL View. Further index changes can be evaluated using actual execution plans and endpoint measurements.

For the consolidated evidence and test scope, see [Lazy Loading Performance Test Results](LAZY_LOADING_PERFORMANCE_TEST_RESULTS.md).

## 9. Deployment Architecture and Production Readiness — Docker, Nginx and FastAPI Scaling

### Application workers and container deployment

- The development configuration used **four Uvicorn worker processes** on one host. Each worker runs as a separate process; aggregate SQL Server connection demand depends on each process's SQLAlchemy pool configuration.
- **Docker** is the proposed deployment packaging approach for consistent application runtime dependencies and environment-specific configuration. Container health checks form part of the deployment design.
- **Nginx** was used as a reverse proxy/load balancer in Docker Desktop during local API load testing; a production deployment can use the same architectural pattern with production-specific configuration. Its production configuration can provide TLS termination, upstream request routing and request/timeout controls.
- The SQL Server database (`MandaiDB`) remains the shared source of truth for product data, orders, inventory and transaction records.

### Proposed containerized deployment topology

```text
Flutter Web / Android / Desktop Clients
                  |
                HTTPS
                  |
            Nginx Reverse Proxy
           /         |         \
          v          v          v
    Docker App 1  Docker App 2  Docker App N
      FastAPI       FastAPI       FastAPI
      Uvicorn       Uvicorn       Uvicorn
      workers       workers       workers
           \         |         /
              SQL Server
               MandaiDB

    Stripe Webhooks -> Nginx -> FastAPI -> MandaiDB
```

### Technical approach

- **Load balancing:** Configure Nginx upstream routing across FastAPI instances, with appropriate health monitoring, trusted proxy headers, TLS certificates and allowed CORS origins. Verify instance failure and recovery behavior in the target deployment.
- **Worker and connection capacity:** Tune the number of Uvicorn workers, SQLAlchemy pool size, overflow limits and timeouts together, accounting for the total number of containers and SQL Server connection capacity.
- **Stateless application instances:** Keep transactional business state in shared SQL Server storage. For multiple containers, evaluate shared/object storage for product images and media so each instance serves consistent content.
- **Concurrent checkout:** Maintain atomic stock updates, database transactions and persistent idempotency records across workers and instances to protect order consistency and prevent overselling.
- **Stripe webhook processing:** For the proposed multi-instance deployment, route webhook deliveries through Nginx, verify Stripe signatures, and validate persistent event deduplication/idempotency across instances under retry scenarios.
- **Performance and resilience:** Evaluate throughput, latency, connection-pool behavior, health checks, resource utilization and error rates using representative workloads, including combined catalog filtering and sorting.

### Production readiness

The deployment approach uses **Docker, Nginx reverse proxy/load balancing, and multiple FastAPI instances/workers**. Nginx in Docker Desktop with five local FastAPI instances has been exercised for read-only API load testing; the production topology remains subject to environment-specific configuration and validation. Production readiness requires further integration, performance, security, failover and load testing using the **actual production dataset and expected user workload, hardware resources, network conditions, SQL Server capacity, and deployment configuration**. Validation should cover Nginx routing, container lifecycle, connection pools, shared media, HTTPS, secrets management and Stripe webhook delivery.

**Evidence status:** Development included a four-worker Uvicorn configuration. A separate local, non-production k6 benchmark used Nginx in Docker Desktop to route requests to five FastAPI/Uvicorn instances (ports 8000–8004). Production containerization, resilience and sizing require validation using the actual production dataset, hardware, traffic and configuration. See [Product Catalog API Load Test Report](MANDAI_PRODUCT_CATALOG_API_LOAD_TEST_REPORT.md).

## 10. Direct API Stress Test — Observed Read-Only Throughput

The read-only product catalog endpoint (`GET /api/products`) was tested against the local FastAPI server at concurrency levels of **5, 10, 20, 50 and 100 simulated users**, with **200 requests per stage**. The results showed **200/200 successful responses and zero errors at every stage**. At the highest tested concurrency (**100 simulated users**), the observed throughput was approximately **330 requests per second (RPS)**.

These figures describe **concurrent request-generation load and measured HTTP throughput** in the tested development configuration. They are separate from SQL-only sorting measurements and Flutter lazy-loading/rendering measurements. They also represent a read-only endpoint, rather than checkout or payment throughput. Production capacity should be established through load testing with the actual dataset, hardware, deployment configuration, request mix, and target response-time requirements.

### Multi-instance Nginx/k6 load-test evidence

A separate local, non-production load test used **Nginx in Docker Desktop** and **five FastAPI/Uvicorn instances** (ports 8000–8004), exercising `GET /api/products?limit=10&offset=0` with gradual ramp-up targets of **300, 500 and 700 virtual users**. The 700-VU run completed **27,691 HTTP requests**, with **zero HTTP request failures**, **395.52 average RPS** and **2.45-second P95 HTTP latency** over the full ramp-up/hold/ramp-down scenario. These are read-only HTTP API measurements, separate from SQL-only benchmarks, adaptive UI batch sizes and Flutter rendering. See [Product Catalog API Load Test Report](MANDAI_PRODUCT_CATALOG_API_LOAD_TEST_REPORT.md).

## 11. Stripe Payment Gateway (Sandbox)

Stripe Test Mode integrates with Stripe's real payment APIs to demonstrate checkout, payment status handling, and test-card transactions without charging real funds. Production operation requires live credentials, secure webhook validation, and testing against the target production environment and configuration.

## 12. Engineering Evidence and Validation Scope

Engineering evidence includes:

| Area | Evidence available | Scope |
| --- | --- | --- |
| Catalog API | Reviewed FastAPI endpoint signature and SQLAlchemy ordering/pagination logic | Server-side filter/sort/pagination behavior |
| SQL Server indexes | SSMS index inventory and active-category index creation | Four named indexes on `dbo.Products` |
| Combined SQL performance | 8 scenarios × 5 runs, 40 executions | Synthetic read-only SQL benchmark; 1–18 ms, weighted average 2.83 ms |
| Read-only HTTP stress | Five concurrency stages, 200 requests each, zero errors | Up to 100 simulated concurrent users, approximately 330 RPS at the highest stage |
| Purchase concurrency | Concurrency test, 20 requests against stock of 10 | 10 accepted and 10 rejected; no overselling in that scenario |
| Flutter | Static analysis and unit/widget test results measured during development | 8 tests passed in the measured run; end-to-end UI latency measured separately if required |
| Nginx and multiple API instances | Local k6 load-test report: Nginx in Docker Desktop, five FastAPI instances, up to 700 VUs | Read-only catalog HTTP traffic; production deployment requires environment-specific validation |

Production readiness requires testing under the actual product data volume, traffic patterns, hardware and deployment configuration, including multi-device UI, checkout, webhook retries, security, performance, resilience and monitoring. Configure production HTTPS, secrets management and webhook verification according to the deployment design.

## 13. Technical Decisions and Trade-offs

- **Flutter:** Reuses UI code across platforms, while native features and device layouts may need platform-specific work.
- **FastAPI:** Typed REST endpoints, configurable Uvicorn worker processes, and container-based deployment with Docker and Nginx as the proposed reverse proxy/load balancer.
- **SQL Server:** Strong transactional integrity for purchase and stock consistency; correct indexing and connection-pool configuration matter under load.
- **Modular application:** Keeps the focused assessment deployable as a single backend service, with independent worker/instance scaling as a future deployment option.
- **Soft deactivation:** Supports retention of products referenced by historical transactions where the corresponding backend and database rules are implemented.
