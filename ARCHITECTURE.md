# Mandai E-Merchandise — Node.js Architecture and Engineering Review

**Context:** Independent coding assessment, Question 5  
**Architecture described:** Local Node.js migration candidate, not the original submitted FastAPI variant  
**Review date:** 5 November 2026  
**Status:** Documented source implementation and selected local verification; not a production certification.

## 1. Executive architecture decision

The candidate separates Flutter presentation, an NGINX HTTP gateway, Node.js services, Redis catalog caching, and transactional persistence in a **single existing Microsoft SQL Server `MandaiDB`**. The separation is at the **service/process deployment boundary**; a shared database means it is **not** a database-per-service implementation. The application separates read-heavy catalog traffic from write-heavy commerce/payment concerns. Stripe is used in **Test Mode** only.

**Measured design implication:** In the 5 November 2026 local Docker `GET /api/products` comparison, both Node.js and FastAPI satisfied 23/23 levels with 17,435 correct responses and no recorded errors. FastAPI had higher RPS in 19/23 stages and lower P95 in 17/23. **The evidence does not support claiming Node.js is faster**. It supports choosing based on service boundary and development/operability trade-offs, subject to retesting in actual deployment environments. See [the benchmark](fastapi_vs_nodejs_benchmark.md).

## 2. Reviewed local topology

```text
Flutter web / Android / desktop UI
            |
            | HTTP (local development)
            v
NGINX Docker gateway (:8080; Windows host :51872)
            |
            +-- Catalog GET routes --> catalog1..catalog4 Node.js instances
            |                              | Redis cache-aside (optional/configured)
            |                              +----> SQL Server MandaiDB on miss
            |
            +-- Commerce: cart checkout / purchases / orders / Stripe
            |       --> commerce1, commerce2 (Node.js; DB transactions)
            |
            +-- Admin / Identity Node.js services (routing per deployed NGINX config)
            |
            +-- Payment-return and webhook routes (configured gateway paths)

All services requiring persistence --> existing MandaiDB
Catalog cache invalidation --> shared Redis generation key
Stripe Checkout --> Stripe Test Mode; webhook and explicit reconciliation
```

**Observed:** Commerce containers `mandai-node-candidate-commerce1-1` and `commerce2-1` had no bind mounts (empty `.Mounts`). Source changes therefore require **image rebuild/container recreation**, not just `docker restart`. Service names and upstream paths are taken from the supplied local environment/source context; exact deployed Compose/NGINX routing should be verified from its active configuration before production claims.

## 3. Components and responsibilities

| Component | Reviewed responsibility | Evidence / boundary |
|---|---|---|
| Flutter/Dart | Customer storefront, admin inventory views, shopping cart, orders, Stripe test checkout | Uploaded `shell*.dart`, `stripe_checkout_client.dart` |
| NGINX | Entry point for service routing, browser preflight/CORS, container gateway | Local Docker gateway and recorded HTTP behavior; full active config not supplied here |
| Node.js Catalog | Read APIs with filtering and pagination; Redis-backed responses | `catalog-service.js` references, `cache.js` |
| Node.js Identity | Login and access control | `server.js` composition, `routes.js` and tests |
| Node.js Admin | Product management through restricted routes | Source composition and route references; full deployment not independently audited |
| Node.js Commerce | Purchase, checkout, orders, Stripe session lifecycle and reconciliation | `stripe-checkout-service.js`, `stripe-repository.js` |
| Redis | Cached catalog responses; generation invalidation, 5-s TTL configurable | `cache.js`, `server.js` |
| SQL Server | Authoritative products, reserved inventory, orders, attempts, payments, events/outbox | `db.js`, repository SQL, user-provided SQL SELECT results |
| Stripe | Hosted Checkout **test** sessions, session retrieval/expiration, webhook verification | `stripe-gateway.js`, test-mode session checks |

## 4. Design approach and maintainability

Reviewed modules exhibit **separation of HTTP interface, application orchestration, domain validation, infrastructure adapters, and SQL repositories**. This is consistent with selected Clean Architecture, dependency-injection and SOLID principles, but the entire repository and dependency graph were not audited. Do not claim full DDD/Clean Architecture compliance or uniform BLoC usage throughout every Flutter feature without additional inspection.

The implementation uses feature-oriented Flutter views, stateful shell logic, a dedicated Stripe HTTP client and deep-link handler. Some cart and checkout state resides in `_ShellState` and `_ShellCustomer`, creating UI coupling that is a target for further refactoring, rather than proof of complete presentation/domain separation.

## 5. Data integrity and concurrent inventory updates

`SqlStripeRepository.reserve()` runs in a SQL transaction: create pending order; read product price; conditionally decrement `Products.Stock` only if available (`Stock >= requested`); insert `OrderItems`; set total and attempt; append `inventory.reserved` outbox event; commit. The price is determined server-side. On transaction failure the wrapper rolls back. Review of the code establishes the control path; full production race testing for every service combination is not supplied.

`settle()` verifies Stripe **test-mode** session identity, order reference, amount, currency and paid status, checks an existing payment reference, and commits a payment record plus status transitions and `payment.completed` event. `release()` requires a verified unpaid Stripe state, checks for existing payment and terminal status, restores each reserved product quantity, updates order/attempt and records `inventory.released`. Status and affected-row guards mitigate duplicate stock restoration; they are not substitutes for operational reconciliation and fault-injection testing.

**Source evidence:** `stripe-repository.js`, `stripe-policy.js`, `db.js`. Transactions use `mssql`; the supplied source does not implement distributed transaction coordination across SQL and Stripe.

## 6. Payment lifecycle and eventual consistency

```text
Customer checkout request + idempotency key
  -> SQL stock reserve/order attempt COMMIT
  -> Stripe Test Mode Checkout Session creation
  -> save Stripe session reference
  -> Stripe hosted checkout / return (return URL is not payment proof)
  -> webhook or authenticated reconciliation (Stripe state verified)
       -> paid: settle exactly one approved_test payment + paid/completed
       -> expired/unpaid: restore reserved stock + expired order/attempt
       -> uncertain: retain review/pending; do not create another payment
```

The database commit and external Stripe operation do not share one atomic transaction; uncertain results require an explicit review/reconciliation path. The browser return page does not prove settlement. Observed 5 November troubleshooting showed a strict Express JSON-parser rejection when Flutter sent JSON literal `null` for a no-body POST. The client change to omit the body corrected that source-level defect; no claim is made that every final frontend/browser variant was retested.

**Recorded integration evidence:** 3380–3382: Stripe test `complete/paid`, matching references/amounts; read-only `checkSession` PASS. A **real SQL settlement dry run** returned `settled` followed by explicit rollback. A later SQL SELECT showed all three orders `completed`, attempts `paid`, and exactly one `approved_test` Payments record each. This demonstrates those local records reached consistent payment state, not a production SLA or broad reliability guarantee.

## 7. Redis cache consistency

`RedisCatalogCache` uses a read-through/cache-aside `getOrLoad()` with configurable short TTL (default 5 seconds), one in-flight load per key per process, Redis generation key `mandai:catalog:generation`, and a SQL fallback on Redis error. Generation increments invalidate the prior key namespace without `FLUSHALL`. SQL Server is authoritative; Redis never owns transactional stock.

**Engineering requirement:** a successfully committed SQL reservation or inventory release must lead to catalog invalidation; frontends must **refetch** changed catalog data. Previously reviewed `server.js` constructed `StripeCheckoutService` without injecting `cache`. A separate corrective patch was prepared; the supplied evidence does not establish that the patched Docker image, shared Redis configuration and UI refresh subsequently passed an end-to-end test. Therefore cache consistency after every Stripe cancellation is **verification outstanding**. Redis write/invalidation failure should be monitored and healed by bounded TTL/event replay rather than assuming zero stale responses.

## 8. Authentication, authorization and security

JWT/auth middleware and role checks restrict protected operations. CORS is a browser origin policy, not authorization. The Node.js `server.js` uses Express `cors`, `express.json({limit:'256kb'})`, and a **raw-body Stripe webhook route registered before JSON parsing**. Stripe gateway configuration restricts test keys/test sessions; webhook verification rejects live-mode events. HTTPS, secret storage and key rotation are necessary for hosted deployment. No credentials, private signing materials or user tokens belong in documentation.

## 9. Deployment operations and failure modes

- **Local tested host:** Windows/Docker Desktop; Node gateway port `51872`, FastAPI comparison port `52001`. Flutter web has been used on host port `8085`; Android emulator `10.0.2.2` is the host-loopback adapter and is not a cloud endpoint.
- Commerce containers had no bind mounts. Applying source patches requires rebuilding the images and recreating the correct Compose services. Restarting old images does not update code.
- Redis/client connection faults are handled with SQL fallback on catalog GETs, but cache invalidation and failure visibility still require production tests.
- Stripe webhook delivery, idempotency, retries, eventual consistency, SQL availability and order payment state recovery require explicit monitoring and reconciliation playbooks.
- The `PaymentOutbox` table is written in the reviewed transaction code. **Do not describe an externally deployed Kafka broker, guaranteed published events or a completed outbox worker without evidence**.

## 10. Objective FastAPI-vs-Node.js evaluation

Both applications were benchmarked on **the same local host** in separate Docker/NGINX setups on 5 November 2026. Recorded Python test results: 23/23 levels PASS; 17,435 successful reads per deployment; 0 HTTP errors; FastAPI peak **1,105.07 RPS**, Node.js peak **995.36 RPS**; at 2,000 workers **1,042.74 vs 991.78 RPS**, and **117.56 vs 121.95 ms P95**, respectively. Across stages FastAPI had higher throughput at **19/23**, and lower P95 at **17/23**. These are **measured outcomes** and should not be diluted into an unsubstantiated Node.js performance advantage.

The local host was shared, but CPU, memory, process count, DB/Redis state, Docker quotas and warmed-cache parity were not independently proved identical. These results evaluate **the two tested configurations**, not inherent runtime efficiency. Different hardware, infrastructure, managed services or settings in **Azure or AWS** can change both outcomes; no Azure/AWS measurement was supplied. Host-specific regression and performance tests are required before deploying to those services. Full per-stage data: [benchmark](fastapi_vs_nodejs_benchmark.md).

## 11. Remaining verification and production-readiness gates

1. Record the exact Docker image hashes, Node.js versions, worker counts, CPU/RAM quotas, NGINX config, SQL/Redis topology, cache hit rates and test command for repeatability.
2. Run final-build Node.js unit and API suites with captured pass/fail totals; complete authenticated purchase and concurrent idempotency/oversell integration tests on disposable data.
3. Verify Stripe webhook retries, expired/paid races, double cancellation, SQL rollbacks, outbox consumption, and recovery from network partitions.
4. Verify inventory SQL-to-Redis invalidation and Flutter catalog/cart refresh end-to-end, including pagination and cart items absent from the current page.
5. Run security validation, secret rotation, TLS, deployment health/recovery, multi-node and cloud load tests; establish operational SLOs separately.

**Decision statement:** This Node.js candidate has a credible modular service structure and passed the recorded local catalog load study, while FastAPI showed a higher measured read-only performance more often. Final platform selection is workload- and team-specific; no production superiority or parity is asserted.

**Author:** Yongky (project attribution as supplied).  
**Source and scope:** [SOURCE_MANIFEST.md](SOURCE_MANIFEST.md).
