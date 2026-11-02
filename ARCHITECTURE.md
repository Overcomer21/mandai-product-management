# Mandai Merchandise — Architecture

**Assessment:** Mandai Wildlife Group — Coding Assessment, Question 5

## 1. Architecture Overview

```text
Flutter storefront / administrator UI
                 |
                 v
       NGINX reverse proxy
    Docker :8080 / host :52000
                 |
        +--------+-------------------+
        |                            |
  Catalog GET routes           Auth / admin / checkout /
        |                      orders / Stripe / media
        v                            |
  least_conn upstream                v
  FastAPI Catalog             Main FastAPI :8000
  :8100 :8101 :8102 :8103            |
        |                            |
        v                            |
  Shared Redis cache                 |
        |                            |
   +----+----+                       |
   |         |                       |
  HIT       MISS                     |
   |         |                       |
Return     Query MandaiDB <----------+
cached      and populate cache
response

MandaiDB is authoritative for catalog, inventory and transactions.
Stripe Test Mode is handled by the main FastAPI backend.
```

The current development branch uses a shared Flutter frontend, a main FastAPI backend, and a separately runnable read-only Product Catalog FastAPI service behind NGINX. Redis provides shared catalog caching, while SQL Server remains the authoritative transaction and inventory database. Frontend code uses modular organization, repositories, and BLoC patterns in selected areas. The architecture description is scoped to the features and evidence reviewed.

## 2. Clean Architecture Principles and VGV Engineering Practices

The application follows **Clean Architecture principles** by promoting separation of concerns and organizing selected features around presentation, state management, and data access. The documented approach is pragmatic and modular; full layering across every screen requires a separate source-code audit.

Selected **Very Good Ventures (VGV) engineering practices** include:

- **BLoC-based state management:** Separates application state and business workflows from UI components in applicable features.
- **Repository pattern:** Organizes access to backend APIs and data behind reusable repositories.
- **Modular, maintainable code:** Encourages reusable components and clearer feature boundaries.
- **Automated testing and static analysis:** Helps validate behavior and improve code reliability.

## 3. Main Components

- **Presentation:** Customer catalog, shopping cart, and administrator dashboard.
- **Main API (port 8000):** Authentication, administrator CRUD, purchases, checkout, orders, Stripe-related routes, product media and health.
- **Product Catalog service (ports 8100–8103):** Read-only customer catalog endpoints, independently scalable behind NGINX.
- **NGINX (Docker):** Path-based reverse proxy, `least_conn` catalog balancing, upstream retry/failover and browser CORS handling.
- **Redis:** Shared cache for read-heavy catalog responses; not a transactional store.
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

Server-side price and stock validation remain responsibilities of the main transactional backend. Checkout concurrency results are outside the scope of Product Catalog microservice performance evidence.

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

**Verification approach:** Confirm selected batch sizes, offsets, scroll-triggered requests, cancellation/stale-response behavior, filtering across page boundaries, retry handling, and UI frame times against the final application build. These checks are specific to the deployed Product Catalog service.

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
| `IX_Products_Category_Active_Price` | `Category, IsActive, Price` | Category/active filtering with price ordering |

These are ordinary SQL Server indexes, not indexed views. Their actual use depends on the SQL Server query optimizer and query shape. The additional `IX_Products_Category_Active_Price` nonclustered index was created to support category/active filtering and price ordering without changing product master data.

### Performance verification boundary

The pagination, filtering, sorting and indexing mechanisms above describe the catalog design. Product Catalog performance evidence is scoped to the local NGINX entry point **52000**, catalog instances **8100–8103**, shared Redis caching and `MandaiDB`.

## 9. Implemented Product Catalog Microservice, Redis and NGINX Deployment

### Implemented local topology

The `mandai-redis-microservices` branch separates **customer-facing read-only Product Catalog** traffic from the existing main FastAPI backend. The new catalog entry point is `backend/app/product_catalog_main.py`; Redis caching is implemented in `backend/app/catalog_redis_cache.py`. The canonical NGINX configuration is `backend/catalog-nginx.conf`.

| Component | Current local configuration | Responsibility |
| --- | --- | --- |
| Flutter Web | Port 8085 | Storefront and administrator UI |
| NGINX | Docker container `mandai-catalog-nginx-lb`, container 8080 / host 52000 | Reverse proxy, CORS and catalog load balancing |
| Product Catalog service | FastAPI processes 8100, 8101, 8102, 8103 | Read-only product catalog and Redis-backed caching |
| Main FastAPI | Port 8000 | Authentication, administrator CRUD, purchases, orders, checkout, Stripe and product media |
| Redis | Shared cache (endpoint configuration environment-dependent) | Cache catalog reads; not authoritative storage |
| SQL Server | Existing `MandaiDB` | Shared authoritative product, stock, order and payment data |

**Routing:** NGINX's `catalog_backend` uses `least_conn` with four catalog upstreams. The current configuration includes `max_fails=30 fail_timeout=5s`, `proxy_next_upstream error timeout`, `proxy_next_upstream_tries 4` and `proxy_next_upstream_timeout 5s`. Specific main-backend paths are proxied to 8000; `/media/` also goes to 8000, with duplicate upstream CORS headers suppressed. These settings provide passive upstream failure detection and retry for eligible failures, rather than active periodic health checks. The `/` fallback routes unmatched paths to the catalog upstream. This preserves the existing admin/transaction behavior and media-serving route.

**Service boundary:** The catalog service is separated at the FastAPI process and deployment entry-point level, allowing its read-heavy workload to scale without multiplying the main checkout/admin backend. The database is **intentionally shared** for this assessment extension. No independent database ownership, event-driven messaging, Kafka integration, or separate catalog write API is claimed. The catalog service must not be described as responsible for administrator product CRUD or payment processing.

**Container boundary:** NGINX is running in Docker Desktop. The four catalog backends run as separate FastAPI processes; they are not described as individually containerized. NGINX configuration inside the current container is not backed by a bind mount, so the checked-in `backend/catalog-nginx.conf` must be explicitly supplied on container recreation.

### Redis consistency and operational considerations

Catalog requests use a cache-aside flow: the catalog FastAPI process checks Redis; a cache hit returns the cached catalog response, while a cache miss reads from `MandaiDB` and may populate the shared cache before returning the response. Redis is a performance cache; `MandaiDB` remains authoritative for catalog and inventory values. Purchase and stock updates remain transactional in the main backend, and catalog cache responses are not authoritative for checkout. For production readiness, adjust and retest cache expiry, invalidation following administrator updates, and Redis availability and recovery under the intended deployment conditions.

### Production readiness

The Product Catalog Microservices architecture, including NGINX load balancing, Redis shared caching, service routing, and CORS configuration, has been implemented and validated in the local development environment.

For **production readiness**, environment-specific configuration adjustments and additional testing are required, including HTTPS, secrets management, CORS allowlists, cache consistency following administrator updates, Redis availability, service health and failover, SQL Server connection pools, shared media access, Stripe webhook handling, container lifecycle management, and performance testing under the intended production infrastructure and workloads.

## 10. Technical Decisions and Trade-offs

- **Flutter:** Reuses UI code across platforms, while native features and device layouts may need platform-specific work.
- **FastAPI:** Typed REST endpoints, configurable Uvicorn worker processes, and NGINX routing with Docker-hosted NGINX in the tested local setup.
- **SQL Server:** Strong transactional integrity for purchase and stock consistency; correct indexing and connection-pool configuration matter under load.
- **Service separation:** Retains the existing main FastAPI transactional/admin backend while extracting the read-only customer Product Catalog into a separately runnable service; both currently share `MandaiDB`.
- **Soft deactivation:** Supports retention of products referenced by historical transactions where the corresponding backend and database rules are implemented.

**Author:** Yongky
