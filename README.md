# Mandai E-Merchandise — Node.js Migration Candidate

**Independent implementation:** Mandai Wildlife Group coding assessment, Question 5 (not an official Mandai Wildlife Group product).
**Current documentation focus:** Node.js Docker service candidate with Flutter UI, Redis, NGINX, Microsoft SQL Server and Stripe **Test Mode**.
**Documentation updated:** 6 November 2026.
**Status:** Non-production proof of concept; AC01–AC08 functional acceptance is the current verification focus. Full Stripe payment lifecycle validation is deferred, as described below.

## Overview

The application offers a customer product catalog, shopping cart, role-protected administration, purchase/checkout and order-history flows. The Node.js candidate separates catalog read workloads from commerce, identity and administrative responsibilities using an NGINX gateway. It retains the **existing single SQL Server `MandaiDB`** as authoritative persistent storage, with Redis as a short-lived catalog cache. Flutter supplies a common customer/admin frontend. Stripe-hosted Checkout operates **only in sandbox/test mode**.

This is a **migration candidate**, not a statement that the original submission was built in Node.js. The historical FastAPI implementation and its historical assessment evidence are retained as predecessor context, not attributed to Node.js.

## Technology and deployed local roles

| Layer | Technology | Role |
|---|---|---|
| User interface | Flutter / Dart | Responsive customer and admin UI |
| Gateway | NGINX in Docker | HTTP service routing, catalog distribution, browser CORS |
| Backend | Node.js / Express | Catalog, commerce, identity and admin services |
| Catalog optimization | Redis | Cache aside, 5-second default TTL, generation invalidation |
| Database | Microsoft SQL Server (`MandaiDB`) | Authoritative products, inventory, orders, payments and outbox |
| Card-payment demonstration | Stripe Checkout **Test Mode** | Test sessions and status verification; no real charges |
| Test runner | Python `mandai_stress_test.py` | Recorded read-only GET benchmark vs FastAPI |

## Local architecture

```text
Flutter -> NGINX (host :51872 / container :8080)
             |-- Catalog GET -> four Node.js catalog instances -> Redis -> MandaiDB
             |-- Identity, Admin -> Node.js services ------------> MandaiDB
             |-- Orders, Purchases, Stripe -> Node.js Commerce --> MandaiDB
             +-- Payment return and Stripe webhook (configured paths)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for service boundaries, transactional stock handling, cache consistency, webhooks, idempotency, security and production-readiness gaps.

## Implemented and reviewed features

- Catalog read APIs: products, count, categories, detail, filtering, ordering and offset pagination.
- Administrator create/read/update/delete (CRUD), subject to role checks and SQL Server referential-integrity protection; deletion of transaction-linked products is rejected.
- Authenticated purchases and cart checkout with server-side pricing and conditional SQL stock updates.
- Stripe Test Mode checkout/session, reconciliation, cancellation and webhook code paths are implemented or partially exercised; the full payment lifecycle is **not yet end-to-end validated** (see scope note below).
- SQL Server transactions and idempotency checks; `PaymentOutbox` records inventory/payment events.
- Redis generation-based invalidation **supported by the cache**, while full propagation through all Stripe/Flutter paths is subject to final deployed validation.
- Flutter responsive catalog, shopping cart, orders, payment-return deep link and incremental catalog loading. Mobile/desktop claims are platform-dependent.

## Acceptance scope and Stripe payment lifecycle limitation

**Current priority: AC01–AC08 functional acceptance.** Verification concentrates on public/customer catalog operations, filtering/sorting/pagination, administrator CRUD and authorization, customer purchase/order behavior, server-side price and stock validation, transactional idempotency, and prevention of overselling. The Node.js acceptance evidence includes the recorded **44/44 executed API checks passing**, **11 Flutter unit/widget tests passing**, and the **1,000-attempt SQL concurrency retest** (29 accepted, 971 out-of-stock rejections, zero unexpected outcomes, final stock zero). See [APPLICATION_ACCEPTANCE_TEST_RESULTS.md](APPLICATION_ACCEPTANCE_TEST_RESULTS.md) for the test-specific evidence and qualifications. These results are **local functional checks**, not production certification.

**Stripe payment end-to-end lifecycle: OUT OF SCOPE for the current completion claim.** The application includes Stripe **Test Mode** integration and selected checkout/payment, reconciliation, cancellation and inventory-restoration tests have been recorded. However, those partial results **do not establish comprehensive end-to-end payment lifecycle correctness**, including all asynchronous webhook sequences, duplicate/out-of-order events, external provider/network failures, uncertain session creation, abandoned or expired sessions, payment-state reconciliation, exactly-once stock release and recovery after interruptions.

**Further testing and potentially targeted code modifications are required** before the Stripe payment lifecycle can be considered fully verified. Any changes should preserve confirmed payment/stock safety rules, idempotency and order history, and be validated with integration, failure-injection and regression tests. This limitation **does not negate the separately documented AC01–AC08 checks**; it expressly limits what is being claimed about full Stripe processing.

## Recorded testing — important distinction

**Node.js vs FastAPI paired catalog comparison, 5 Nov 2026:** On the same local Windows host, in separate Docker/NGINX configurations, **both** passed 23/23 Python read-only load levels, with 17,435/17,435 successful GETs and zero errors per implementation. **FastAPI led in RPS at 19/23 levels and P95 at 17/23 levels.** Peak measured RPS was **1,105.07 FastAPI vs 995.36 Node.js**. Full report: [fastapi_vs_nodejs_benchmark.md](fastapi_vs_nodejs_benchmark.md).

**Node.js Stripe/SQL local diagnostic:** A real `settle()` call on order 3380 returned `settled` in a rolled-back transaction. Later **read-only** DB checks reported orders **3380–3382** as `completed`, attempts `paid`, each with **one** `approved_test` payment. These were sandbox payment records. This does not establish production payment readiness.

**Acceptance evidence attribution:** The Node.js AC01–AC08 checks and fresh Node.js/SQL overselling retest are documented in [APPLICATION_ACCEPTANCE_TEST_RESULTS.md](APPLICATION_ACCEPTANCE_TEST_RESULTS.md). Results from the earlier FastAPI assessment remain historical and must not be presented as new Node.js test passes. The separately recorded FastAPI-versus-Node.js GET benchmark is comparative performance evidence, not a Stripe payment end-to-end acceptance result.

## Quick local inspection (read-only)

Run from the project directory on Windows PowerShell. These commands only inspect existing processes/health and source; they do not rebuild images or alter data.

```powershell
cd C:\UIPath\mandai-product-management_nodejs\Mandai-NodeJS-Migration
docker compose -f .\deploy\docker-compose.yml ps
curl.exe -i http://127.0.0.1:51872/health
docker compose -f .\deploy\docker-compose.yml config --services
```

`docker compose -f .\deploy\docker-compose.yml config --services` applies to the Compose file selected in the current directory/environment; verify actual file and project name before making changes. **Do not use `docker restart` as a substitute for image rebuild** if a container has no bind mounts.

For Flutter Web (from `C:\UIPath\mandai-product-management_nodejs\frontend`):

```powershell
flutter analyze
flutter test
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8085 --dart-define=API_BASE=http://127.0.0.1:51872
```

The Flutter web-server command prints a local URL to open manually in a separate Chrome window.

For Android Emulator, the typical host alias is `10.0.2.2`: `--dart-define=API_BASE=http://10.0.2.2:51872`. Android cleartext policy, Stripe return URL/deep linking, emulator/ADB availability and SDK configuration need separate checks. The exact supported Flutter command should be checked against the installed SDK and project settings.

## Stripe Test Mode operational safety

- Test checkout events **do not transfer live funds**. Never publish API keys, webhook signing material, JWT secrets or customer data.
- The payment-return browser page is **not proof of payment**; an authenticated reconciliation or verified Stripe webhook must determine the result.
- A paid checkout must not be canceled or have reserved inventory returned. If a session is confirmed expired/unpaid, release must occur at most once.
- If the external Stripe result is unknown, stop retrying new payments and reconcile the existing attempt first.
- Order and payment records must not be deleted simply to clear a pending UI state.

## Documentation index

- [SPEC.md](SPEC.md) — requirements and assessment scope of the Node.js migration candidate.
- [ARCHITECTURE.md](ARCHITECTURE.md) — reviewed architecture, design decisions, data safety and benchmark implications.
- [APPLICATION_ACCEPTANCE_TEST_RESULTS.md](APPLICATION_ACCEPTANCE_TEST_RESULTS.md) — evidence matrix separating Node.js and historical FastAPI outcomes.
- [LAZY_LOADING_PERFORMANCE_TEST_RESULTS.md](LAZY_LOADING_PERFORMANCE_TEST_RESULTS.md) — pagination, historical SQL benchmark and remaining Node.js/Flutter validation.
- [fastapi_vs_nodejs_benchmark.md](fastapi_vs_nodejs_benchmark.md) — unmodified measured metrics in engineering interpretation.
- [SOURCE_MANIFEST.md](SOURCE_MANIFEST.md) — source provenance, evidence classification and limitations.

## Production qualification

No Azure/AWS deployment measurements or production safety/capacity certifications were provided. Host hardware, available vCPUs, network RTT, SQL/Redis placement, cache behavior, concurrency and autoscaling can change results. Plan production-grade observability, cloud-specific performance/chaos testing, TLS, managed secrets, recovery and secure payment workflows before deployment.

**Author:** Yongky (per original documentation).
