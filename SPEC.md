# Mandai E-Merchandise — Node.js Candidate Functional and Technical Specification

**Assessment context:** Question 5, full-stack product management  
**Document type:** Candidate implementation specification, revision 5 November 2026  
**Important distinction:** Describes the Node.js migration candidate and documented requirements; **does not rewrite the historical submitted FastAPI implementation**.

## 1. Scope and user journeys

**Customers:** Browse products; search/filter/sort and paginate; view details; authenticate; place items in a shopping cart; review quantities, server prices and delivery details; initiate authorized purchase or test-mode Stripe checkout; view and reconcile previous orders.

**Administrators:** Authenticate, view inventory, create/update/deactivate product entries under server authorization rules, and preserve historical transactional references.

**Platform:** Flutter frontend; NGINX gateway; Node.js services with service-role separation; Redis cache for read catalog operations; one existing SQL Server `MandaiDB`; Stripe **Test Mode**. Flutter deployment targets require independent build and behavior verification.

## 2. Functional requirements

| ID | Requirement | Status/evidence |
|---|---|---|
| FR01 | Public catalog with deterministic pagination, filters, sorting and detail | Node.js source referenced and paired GET load test recorded |
| FR02 | Administrator inventory CRUD and role enforcement | Source/routing present; final Node.js end-to-end run totals not supplied |
| FR03 | Customer authentication and purchase authorization | Source present; final Node.js integration totals not supplied |
| FR04 | Server-side stock/price validation; atomic conditional decrement | SQL repository code reviewed |
| FR05 | Idempotent checkout replay, distinguish same/different payload | Node.js fingerprint and session code reviewed; frontend key-state regression remains a test gate |
| FR06 | Stripe sandbox checkout, paid-state reconciliation and expired/unpaid stock release | Source reviewed; selected local SQL/Stripe diagnostic evidence recorded |
| FR07 | Catalog cache with bounded TTL and generation-based invalidation | `cache.js` source reviewed; deployed end-to-end cache propagation requires verification |
| FR08 | Cart and inventory refresh following confirmed cancel/settlement | Flutter patch prepared; final UI+Redis end-to-end result not supplied |
| FR09 | Auditability of payment and inventory transitions | `PaymentOutbox` writes reviewed; external publishing worker not established |

## 3. Data and transaction rules

- `MandaiDB` is the sole authoritative transactional database, including Users, Products, Orders, OrderItems, Payments, StripeCheckoutAttempts, StripeCheckoutEvents and PaymentOutbox; do not introduce another authoritative datastore.
- Use parameterized `mssql` SQL queries. Conditional stock update must succeed before recording a reservation.
- Commit business state and related outbox row in the same SQL transaction, or roll back on failure.
- Return reserved inventory **only after** session status is verified as expired/unpaid (or independently verified unpaid async failure in the reviewed code) and after confirming no payment already exists; prevent a second release.
- Never equate a browser redirect with successful payment or authorized stock release.
- Cache invalidation is an eventual consistency mechanism, not a substitute for SQL correctness.

## 4. Security and payment requirements

JWT authentication and role enforcement must be performed on the server. Validate all input and money values server-side. Test-mode-only Stripe keys and sessions must be used in the demo; verify webhook signatures with the exact raw request body; reject live events. Configure CORS based on trusted frontend origins and HTTPS/secret management for hosted environments. Do not store any credentials in repository documentation.

## 5. Non-functional requirements and acceptance thresholds

- **Measured local catalog target:** 100% HTTP 200, zero errors, P95 <= 2,500 ms for the supplied one-GET-per-worker Python stages. This is a **test-specific target**, not a production SLA.
- Support responsive Flutter layouts and incremental pagination; measure mobile frame/render performance separately from API latency.
- Monitor availability, SQL pool usage, Redis hit ratio/TTL, payment state transitions and webhook errors before hosted deployment.
- Avoid claiming capacity for 2,000 sustained users from a burst of 2,000 one-shot requests.

## 6. Acceptance criteria and traceability

The prior submission's **AC01–AC08 PASS** results are historical FastAPI evidence. The Node.js candidate targets equivalent user-visible capabilities, but it needs its own final-build acceptance suite. Node.js current evidence is a paired read-only catalog benchmark (23/23 levels; 17,435/17,435 GETs; zero errors), source-reviewed tests, real SQL dry-run rollback, and three verified persisted test-mode payment outcomes. See [APPLICATION_ACCEPTANCE_TEST_RESULTS.md](APPLICATION_ACCEPTANCE_TEST_RESULTS.md) for explicit evidence grades and gaps.

The original assessment additionally required a public source repository and technical architecture/spec documentation. This updated document does **not** imply that a new Node.js version has been submitted or pushed.

## 7. Known constraints and exclusions

- Shared SQL Server database; no claim of independent per-service persistence or distributed ACID transaction with Stripe.
- Stripe Test Mode only; no real payment charge, refund, tax or payment-provider certification.
- No evidence of a deployed Kafka broker or guaranteed asynchronous event publisher despite transactional `PaymentOutbox` writes.
- No supplied Azure/AWS test results; performance and security must be revalidated in hosting environments.
- Cache refresh, cart pagination edge cases, mobile return/deep-link, idempotency key recovery and multi-service race tests are outstanding final-build gates.

**Implementation references:** [ARCHITECTURE.md](ARCHITECTURE.md), [README.md](README.md), [SOURCE_MANIFEST.md](SOURCE_MANIFEST.md).
