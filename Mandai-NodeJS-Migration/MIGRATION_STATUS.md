# API parity status (source-inspection based)

| Path group | Candidate status | Verification |
|---|---|---|
| `GET /api/products[/categories, /count, /:id]` | Implemented | Syntax / unit only; DB integration pending |
| `GET /api/admin/products[/categories, /count, /stats, /:id]` | Implemented | Syntax / unit only; DB integration pending |
| `POST/PUT/DELETE /api/admin/products` | Implemented | DB integration pending |
| `POST /api/auth/login`, `GET /api/account/me` | Implemented | Cryptographic, SQL, auth E2E pending |
| `POST /api/purchases` | Implemented | Fingerprint unit PASS; transactional parity pending |
| `POST /api/checkout` | Implemented | Validation unit PASS; transaction/payment parity pending |
| `GET /api/orders/my`, `/details` | Implemented | SQL integration pending |
| `GET /health` | Implemented with SQL connection check | DB integration pending |
| Stripe checkout/order/cancel/reconcile/resume/webhook/return | NOT implemented | Blocker for Flutter payment parity |
| Testing report/launcher | NOT implemented | Blocker for Run All Tests parity |
| Media product static routes | NOT implemented | Blocker for image/media parity |
| Redis cache | Implemented optional adapter | Redis E2E pending |
| Kafka/outbox | Adapter only, NOT wired | Blocker for requested event pipeline |
| NGINX routing | Example configuration | Docker and load test pending |

**No complete parity or production-readiness claim.** Original FastAPI must remain authoritative until missing features and full regression tests are completed.
