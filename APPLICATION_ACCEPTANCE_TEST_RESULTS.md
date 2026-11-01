# Mandai E-Merchandise — Application Acceptance Test Results

**Assessment:** Question 5 — Full-Stack Product Management  
**Test Coverage:** AC01–AC08  
**Overall Result:** All eight core implementation acceptance criteria are **PASS** for the documented test scenarios and recorded evidence.

## 1. Application Testing Overview

This report summarizes application testing for the **Mandai E-Merchandise Full-Stack Application**, covering frontend UI, backend REST APIs, database integration, security, purchase transactions, concurrency control, and API performance.

Testing was conducted to verify application functionality, reliability, data integrity, and compliance with the defined acceptance criteria (AC01–AC08). Each criterion is mapped to test functions, recorded results, and verification objectives.

## 2. Acceptance Criteria Test Summary

### AC01 — Full-Stack Product Management

**PASS — Summary:** Verified frontend-to-API contracts, product data models, and backend functionality using Flutter, FastAPI, and SQL Server.

| Test Function / File | Result | Purpose |
|---|---|---|
| `app_test.dart` | PASS | Verify storefront navigation and login screen |
| `models_test.dart` | PASS | Verify product and authentication data models |
| `question5_api_contract_test.dart` | PASS | Verify Flutter-to-backend API contracts |

### AC02 — Backend REST API

**PASS — Summary:** Verified product listing, product details, API CRUD operations, request validation, and purchasing endpoints through expected HTTP responses.

| Test Function | Result | Purpose |
|---|---|---|
| `test_auth_and_crud` | PASS | Verify product creation, retrieval, update, and deletion |
| `test_storefront_catalog_and_details` | PASS | Verify public product listing and details |
| `test_customer_buy_atomic_and_replay` | PASS | Verify purchase processing and repeat-request handling |

### AC03 — Administrator Inventory Dashboard

**PASS — Summary:** Verified inventory management operations, including product creation, stock updates, product retrieval, and deactivation.

| Test Function | Result | Purpose |
|---|---|---|
| `test_admin_inventory_crud_and_role_enforcement` | PASS | Verify administrator inventory CRUD and stock updates |
| `test_admin_crud_and_role_protection` | PASS | Verify administrator operations against SQL Server |
| Flutter admin CRUD API contract test (`question5_api_contract_test.dart`) | PASS | Verify GET, POST, PUT, and DELETE request contracts |

### AC04 — Customer-Facing Storefront

**PASS — Summary:** Verified customer product catalog retrieval, product data, search input, and navigation to login.

| Test Function | Result | Purpose |
|---|---|---|
| `test_storefront_catalog_and_details` | PASS | Verify product catalog and product information |
| `Q5 storefront uses public product API` | PASS | Verify customer-facing product API contract |
| `Store search bar renders and accepts text` | PASS | Verify product search input |
| `login screen is rendered after tapping Log in` | PASS | Verify customer login navigation |

### AC05 — Role-Based Administrator CRUD

**PASS — Summary:** Verified that administrators can manage inventory, while unauthenticated users and customers are denied unauthorized operations with HTTP 401 or 403 responses.

| Test Function | Result | Purpose |
|---|---|---|
| `test_auth_and_crud` | PASS | Verify administrator access and product CRUD authorization |
| `test_admin_inventory_crud_and_role_enforcement` | PASS | Prevent customers from modifying inventory |
| `test_admin_crud_and_role_protection` | PASS | Verify SQL Server-backed administrator access restrictions |
| `test_sql_injection_strings_cannot_bypass_login` | PASS | Verify malicious login inputs cannot bypass authentication |

### AC06 — Secure Buy Endpoint

**PASS — Summary:** Verified authenticated purchases, server-side pricing, input validation, and idempotency. Unauthorized purchases are rejected without modifying inventory.

| Test Function | Result | Purpose |
|---|---|---|
| `test_customer_purchase_still_succeeds` | PASS | Verify authorized customer purchase |
| `test_guest_purchase_denied_without_mutation` | PASS | Reject unauthenticated purchase without changing stock |
| `test_admin_purchase_denied_without_mutation` | PASS | Prevent administrator use of customer purchase endpoint |
| `test_purchase_uses_server_side_price` | PASS | Verify purchase amount uses server-side product prices |
| `test_customer_buy_atomic_and_replay` | PASS | Verify idempotency and prevent duplicate orders |

### AC07 — Race Condition Prevention

**PASS — Summary:** Verified concurrent transactions and repeated idempotency keys. Five concurrent retries of one purchase result in one order and a single inventory deduction; failed purchases leave inventory unchanged.

| Test Function | Result | Purpose |
|---|---|---|
| `test_concurrent_same_key_single_purchase` | PASS | Ensure five concurrent retries create only one order |
| `test_duplicate_key_concurrent_retries_only_one_order` | PASS | Prevent duplicate orders during concurrent requests |
| `test_insufficient_stock_atomic_rollback` | PASS | Verify rollback for insufficient stock |
| `test_failed_crud_constraint_rolls_back` | PASS | Prevent invalid inventory updates |
| `test_checkout_same_key_replay_no_duplicate_order_or_payment` | PASS | Prevent duplicate orders and payments on concurrent checkout retries |

### AC08 — Overselling Prevention

**PASS — Summary:** Ten concurrent purchase requests were tested against five units of stock. The expected and verified assertions are five successful purchases (HTTP 201), five rejected purchases (HTTP 409), zero remaining inventory, and five unique orders. Both isolated backend tests and SQL Server integration tests implement this scenario.

| Test Scenario | Verified Assertion |
|---|---|
| Initial inventory | 5 units |
| Concurrent purchase requests | 10 |
| Successful purchases | 5 |
| Rejected purchases (insufficient stock) | 5 |
| Final inventory | 0 units |
| Unique orders created | 5 |
| Overselling | Not observed in tested scenario |

| Test Function | Result | Purpose |
|---|---|---|
| `test_concurrent_buyers_no_oversell` | PASS | Prevent overselling during simultaneous purchases |
| `test_concurrent_cart_orders_not_oversell` | PASS | Prevent overselling during concurrent cart checkout |
| `test_buy_concurrency_no_overselling_sqlite_regression` | PASS | Verify inventory consistency in isolated SQLite tests |
| `test_concurrent_buyers_no_overselling` | PASS | Verify overselling prevention against SQL Server |
| `test_checkout_concurrent_unique_keys_no_oversell` | PASS | Verify inventory, orders, and payments during concurrent checkout |
| Dedicated SQL Server concurrency suite | 6 PASS, 0 FAIL |
| Comprehensive concurrent overselling prevention — 100 buyers × 10 iterations | 10 PASS, 0 FAIL; 1,000 attempts; 300 successful; 700 insufficient-stock rejections; cleanup reported successful | Validate SQL Server concurrency and transactional integrity |


### Comprehensive Concurrent Overselling Prevention Test — SQL Server

**PASS — 10 of 10 iterations.** A dedicated concurrent-purchase test was executed against the configured SQL Server `MandaiDB` using **100 competing buyers per iteration**, **30 units of initial stock per iteration**, and **10 iterations**. This is an additional, larger-scale validation of **AC08 (Overselling Prevention)** and supports **AC07 (Race Condition Prevention)**. Each iteration used its own test setup; the stock quantity was not shared across all 10 iterations.

| Verification metric | Per iteration | Total across 10 iterations |
|---|---:|---:|
| Concurrent purchase attempts | 100 | 1,000 |
| Initial test inventory | 30 units | 30 units per iteration |
| Successful purchases | 30 | 300 |
| Rejected purchases — insufficient stock | 70 | 700 |
| Remaining test inventory | 0 units | 0 units at the end of each iteration |
| Persisted orders | 30 | 300 |
| Units sold | 30 | 300 |
| Approved **demo** payment records | 30 | 300 |
| Reported execution errors | 0 | 0 |
| Iteration result | PASS | 10 PASS, 0 FAIL |

**Consistency checks:** For every iteration, successful purchases matched the number of persisted orders, sold units, and approved demo payment records. Inventory reached zero without a negative balance or more successful purchases than available stock. All 70 excess purchase attempts per iteration were rejected for insufficient stock. **No overselling was observed under these test conditions.**

**Execution evidence:** `python .\scripts\run_q5_100_buyers.py --confirm-mandaidb-tests-only --buyers 100 --stock 30 --iterations 10 --delay 10`. The console reported `Status: PASS` and `Cleanup: True`, with per-iteration execution times between **0.38 and 0.73 seconds** (5.04 seconds summed across iterations, excluding the configured delay and other overhead). The report was written to [`test-results/q5-100-buyers-concurrency.json`](test-results/q5-100-buyers-concurrency.json).

**Scope and data safety:** This test validates concurrent purchase/checkout processing, inventory consistency, and SQL Server transaction integrity using demo payment records. HTTP endpoint throughput and live Stripe payment processing are outside the scope of this test and are assessed separately where applicable. The script reported successful cleanup of disposable test data; independent database verification may be performed to confirm that retained master records remain unchanged. Testing against `MandaiDB` requires explicit authorization and must be restricted to disposable test records without modifying existing master product data. **Additional validation across different workloads, deployment configurations, and failure scenarios may be required to establish production readiness.**

## 3. Product Catalog, Lazy Loading and Performance Verification

The following catalog and performance results extend the evidence supporting **AC02 (Backend REST API)** and **AC04 (Customer-Facing Storefront)**. They are reported as separate performance test activities rather than additional numbered acceptance criteria.

### Product Catalog and Incremental Loading

- **Catalog dataset:** 2,022 product items reported in `MandaiDB`.
- **Implementation:** FastAPI provides server-side category and stock filtering, search, sorting, and `limit`/`offset` pagination. Flutter retrieves catalog data incrementally for browsing and scrolling.
- **Supported ordering:** Default, Name, Price low, and Price high.
- **Database indexes:** `PK_Products` (`Id`), `IX_Products_Name_Id` (`Name`, `Id`), `IX_Products_Price_Id` (`Price`, `Id`), `IX_Products_IsActive_Category` (`IsActive`, `Category`), and `IX_Products_Category_Active_Price` (`Category`, `IsActive`, `Price`).
- **Observation:** Category-filter responsiveness improved after the active-category index was added. This is a qualitative observation; a numeric before-and-after UI benchmark was not recorded.

### Combined Category, Sorting and Pagination SQL Benchmark

**PASS — 40 of 40 read-only SQL executions completed.** Eight combinations were each executed five times. Measurements below are SQL benchmark elapsed times in milliseconds (ms).

| Category | Sorting | Minimum | Average | Maximum |
|---|---|---:|---:|---:|
| All | Default | 3 ms | 6.60 ms | 18 ms |
| All | Name | 2 ms | 2.40 ms | 3 ms |
| All | Price low | 2 ms | 3.60 ms | 5 ms |
| All | Price high | 2 ms | 3.00 ms | 4 ms |
| Apparel | Default | 1 ms | 1.20 ms | 2 ms |
| Apparel | Name | 1 ms | 2.20 ms | 3 ms |
| Apparel | Price low | 1 ms | 1.80 ms | 3 ms |
| Apparel | Price high | 1 ms | 1.80 ms | 2 ms |

**Summary:** Minimum 1 ms; maximum 18 ms; overall average **2.83 ms**, rounded from eight equally weighted five-run scenario averages. The benchmark used conditional `CASE` ordering and counted rows from a paginated subquery. It is a SQL-level comparison rather than an exact replay of the SQLAlchemy-generated API query or a Flutter rendering measurement.

Detailed report: [`LAZY_LOADING_PERFORMANCE_TEST_RESULTS.md`](LAZY_LOADING_PERFORMANCE_TEST_RESULTS.md).

### Product Catalog API Stress and k6 Load Tests — Final Results

**PASS — Read-only catalog API testing through 2,000 configured users/VUs**, with two distinct load-generation methods.

| Test type | Highest tested level | Successful requests | Errors | Throughput | P95 | Result |
|---|---:|---:|---:|---:|---:|---|
| Python concurrent-request stress test | 2,000 concurrent users / 2,000 requests | 2,000/2,000 | 0 | 196.55 RPS | 2,157.45 ms | **PASS** |
| Grafana k6, limited to 300 RPS | 2,000 configured VUs / 2,000 requests | 2,000/2,000 | 0 | 299.96 RPS | 14.90 ms | **PASS** |

The Python final evidence comprises **23 passing stages and 21,080 successful requests** at test levels from 10 through 2,000. The k6 rate-limited final evidence comprises **17 passing stages and 20,400 successful requests** at levels from 400 through 2,000. All listed stages satisfy the internal **P95 ≤ 2,500 ms** threshold and 0-error requirement.

The k6 workload sends one GET per VU and paces requests with `--rps 300`: 2,000 configured VUs do **not** mean 2,000 simultaneously active network connections. The Python and k6 latency measures have different boundaries and should be reported separately. These tests cover read-only `GET /api/products` through four FastAPI/Uvicorn instances behind NGINX (`least_conn`) in a local non-production environment.

Detailed final report and per-level JSON evidence: [`MANDAI_PRODUCT_CATALOG_API_LOAD_TEST_REPORT.md`](MANDAI_PRODUCT_CATALOG_API_LOAD_TEST_REPORT.md).

## 4. Overall Test Results

| Test Category | Recorded Result |
|---|---|
| Core implementation acceptance criteria (AC01–AC08) | 8 PASS |
| Backend API / automated tests (default run) | 24 PASS, 9 SKIPPED |
| SQL Server integration tests (separate opt-in run) | 9 PASS, 1 warning |
| Dedicated SQL Server concurrency suite | 6 PASS, 0 FAIL |
| Comprehensive concurrent overselling prevention — 100 buyers × 10 iterations | 10 PASS, 0 FAIL; 1,000 attempts; 300 successful; 700 insufficient-stock rejections; cleanup reported successful |
| Flutter unit and widget tests | 8 PASS |
| Flutter static analysis | PASS |
| Python read-only API stress test (10–2,000 concurrency levels) | 23 stages PASS; 21,080 successful requests; 0 errors; peak level P95 2,157.45 ms |
| Grafana k6 read-only API load test (400–2,000 configured VUs; 300 RPS limiter) | 17 stages PASS; 20,400 successful requests; 0 errors; 2,000-VU P95 14.90 ms |
| Catalog combined SQL benchmark — 2,022-item dataset | 40/40 executions; 1–18 ms; 2.83 ms overall average |
| Stripe Test Mode checkout and payment persistence | PASS — recorded functional verification |

**Evidence scope:** Acceptance, transaction and frontend results follow their recorded test evidence; the load-test totals are calculated from the included final JSON results. Results from independent suites are not combined into a single aggregate pass count, and a reported PASS applies to the particular scenario and test setup described.

## 5. Final Conclusion

**All eight core implementation acceptance criteria (AC01–AC08) are supported by the recorded test evidence for the documented scenarios.** Frontend tests, backend API tests, SQL Server integration tests, security checks, concurrency tests (including the 1,000-attempt SQL Server run), final API load/stress testing, and catalog performance benchmarks cover the core functional workflows and the tested read-only catalog workload. Authentication, authorization, idempotency, rollback, inventory integrity, race-condition controls, and overselling prevention were validated for the scenarios tested.

This assessment concerns the eight implementation criteria; repository publication and documentation submission are separate delivery requirements.
