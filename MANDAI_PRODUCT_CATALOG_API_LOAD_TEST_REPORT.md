# Mandai E-Merchandise — Product Catalog API Load and Stress Test Final Report

**Assessment:** Question 5 — Full-Stack Product Management  
**Scope:** Read-only Product Catalog API reliability, throughput and latency  
**Environment:** Local Development and Test Environment (Non-Production)  
**Overall result:** **PASS — Python stress test through 2,000 concurrent requests; k6 rate-limited test through 2,000 VUs / 2,000 completed requests**  
**Author:** Yongky

## 1. Objective

Validate `GET /api/products` using the implemented NGINX load balancer, FastAPI application instances and SQL Server database, with explicit response and latency acceptance thresholds. This report records the selected passing final test runs and their scope; each JSON file is retained as primary machine-readable evidence.

## 2. Test Environment and Acceptance Criteria

| Component | Final test configuration |
|---|---|
| Host | Windows development laptop; local non-production environment |
| Entry point | `http://127.0.0.1:51871/api/products` |
| Load balancer | NGINX in Docker Desktop, `least_conn` |
| Application | Four FastAPI/Uvicorn instances: ports 8001, 8002, 8003 and 8004 |
| Database | Microsoft SQL Server (`MandaiDB`) |
| Test clients | Python `mandai_stress_test.py` and Grafana k6 |
| Workload | Read-only product catalog GET; no product/order/payment writes |
| HTTP success criterion | 100% HTTP 200 responses; 0 request errors |
| P95 criterion | At most 2,500 ms per test run (internally selected performance target) |
| Recovery check | Python test suite checks `/health` after each stage |

The 2,500 ms target is an internal benchmark for this assessment, not a stated Mandai production SLA. These tests do not measure Flutter frame rendering, browser image loading, Stripe payment processing, or transaction/overselling concurrency.

## 3. Python API Stress Test — Concurrent Request Workload

**Result: PASS — 23 test levels, 21,080 successful HTTP requests, 0 errors.** Each level used a concurrency setting equal to its request count (one total HTTP request per configured concurrent user). The script independently assessed error rate, P95 latency and post-test health.

| Concurrent users | HTTP 200 / Requests | Errors | RPS | P95 (ms) | Result | Evidence |
|---:|---:|---:|---:|---:|---|---|
| 10 | 10/10 | 0 | 37.55 | 263.19 | **PASS** | [`JSON`](test-results/mandai-stress-results-10-final.json) |
| 20 | 20/20 | 0 | 83.31 | 228.51 | **PASS** | [`JSON`](test-results/mandai-stress-results-20-final.json) |
| 50 | 50/50 | 0 | 180.60 | 234.52 | **PASS** | [`JSON`](test-results/mandai-stress-results-50-final.json) |
| 100 | 100/100 | 0 | 235.81 | 264.14 | **PASS** | [`JSON`](test-results/mandai-stress-results-100-final.json) |
| 200 | 200/200 | 0 | 330.53 | 264.29 | **PASS** | [`JSON`](test-results/mandai-stress-results-200-final.json) |
| 300 | 300/300 | 0 | 362.90 | 465.89 | **PASS** | [`JSON`](test-results/mandai-stress-results-300-final.json) |
| 400 | 400/400 | 0 | 422.07 | 542.20 | **PASS** | [`JSON`](test-results/mandai-stress-results-400-final.json) |
| 500 | 500/500 | 0 | 368.79 | 926.35 | **PASS** | [`JSON`](test-results/mandai-stress-results-500-final.json) |
| 600 | 600/600 | 0 | 483.75 | 611.55 | **PASS** | [`JSON`](test-results/mandai-stress-results-600-final.json) |
| 700 | 700/700 | 0 | 511.56 | 603.13 | **PASS** | [`JSON`](test-results/mandai-stress-results-700-final.json) |
| 800 | 800/800 | 0 | 481.17 | 918.26 | **PASS** | [`JSON`](test-results/mandai-stress-results-800-final.json) |
| 900 | 900/900 | 0 | 441.42 | 1206.82 | **PASS** | [`JSON`](test-results/mandai-stress-results-900-final.json) |
| 1,000 | 1,000/1,000 | 0 | 513.44 | 1056.16 | **PASS** | [`JSON`](test-results/mandai-stress-results-1000-final.json) |
| 1,100 | 1,100/1,100 | 0 | 532.74 | 965.33 | **PASS** | [`JSON`](test-results/mandai-stress-results-1100-final.json) |
| 1,200 | 1,200/1,200 | 0 | 510.58 | 1160.18 | **PASS** | [`JSON`](test-results/mandai-stress-results-1200-final.json) |
| 1,300 | 1,300/1,300 | 0 | 458.36 | 1286.50 | **PASS** | [`JSON`](test-results/mandai-stress-results-1300-final.json) |
| 1,400 | 1,400/1,400 | 0 | 520.21 | 1291.36 | **PASS** | [`JSON`](test-results/mandai-stress-results-1400-final.json) |
| 1,500 | 1,500/1,500 | 0 | 516.62 | 1467.58 | **PASS** | [`JSON`](test-results/mandai-stress-results-1500-final.json) |
| 1,600 | 1,600/1,600 | 0 | 497.53 | 1503.73 | **PASS** | [`JSON`](test-results/mandai-stress-results-1600-final.json) |
| 1,700 | 1,700/1,700 | 0 | 447.34 | 2014.74 | **PASS** | [`JSON`](test-results/mandai-stress-results-1700-final.json) |
| 1,800 | 1,800/1,800 | 0 | 448.19 | 2023.43 | **PASS** | [`JSON`](test-results/mandai-stress-results-1800-final.json) |
| 1,900 | 1,900/1,900 | 0 | 509.99 | 1918.02 | **PASS** | [`JSON`](test-results/mandai-stress-results-1900-final.json) |
| 2,000 | 2,000/2,000 | 0 | 196.55 | 2157.45 | **PASS** | [`JSON`](test-results/mandai-stress-results-2000-final.json) |

**Highest level:** 2,000/2,000 HTTP 200, 0 errors, **196.55 RPS**, **P95 2,157.45 ms**, `/health` HTTP 200. The selected final evidence file is `mandai-stress-results-2000-final.json`.

These figures characterize the finite burst workload and host/test-run conditions; they should not be interpreted as a verified production user-capacity guarantee.

## 4. Grafana k6 — Rate-Limited Catalog Test

**Result: PASS — 17 test levels, 20,400 successful HTTP requests, 0 errors.** Each level uses `per-vu-iterations`, one GET per configured VU, and `--rps 300` to pace request initiation. The k6 thresholds require `http_req_failed = 0`, 100% HTTP 200 checks, completed iterations meeting the requested VUs, and `http_req_duration` P95 no greater than 2,500 ms.

| Configured VUs | Completed requests | HTTP 200 checks | Observed RPS | P95 (ms) | Result | Evidence |
|---:|---:|---:|---:|---:|---|---|
| 400 | 400 | 400 | 299.29 | 10.50 | **PASS** | [`JSON`](test-results/k6-catalog-400-rps300-final.json) |
| 500 | 500 | 500 | 299.17 | 7.66 | **PASS** | [`JSON`](test-results/k6-catalog-500-rps300-final.json) |
| 600 | 600 | 600 | 299.85 | 13.70 | **PASS** | [`JSON`](test-results/k6-catalog-600-rps300-final.json) |
| 700 | 700 | 700 | 299.80 | 8.58 | **PASS** | [`JSON`](test-results/k6-catalog-700-rps300-final.json) |
| 800 | 800 | 800 | 299.59 | 9.69 | **PASS** | [`JSON`](test-results/k6-catalog-800-rps300-final.json) |
| 900 | 900 | 900 | 299.22 | 8.28 | **PASS** | [`JSON`](test-results/k6-catalog-900-rps300-final.json) |
| 1,000 | 1,000 | 1,000 | 299.83 | 9.12 | **PASS** | [`JSON`](test-results/k6-catalog-1000-rps300-final.json) |
| 1,100 | 1,100 | 1,100 | 299.40 | 8.53 | **PASS** | [`JSON`](test-results/k6-catalog-1100-rps300-final.json) |
| 1,200 | 1,200 | 1,200 | 299.82 | 9.51 | **PASS** | [`JSON`](test-results/k6-catalog-1200-rps300-final.json) |
| 1,300 | 1,300 | 1,300 | 299.52 | 10.73 | **PASS** | [`JSON`](test-results/k6-catalog-1300-rps300-final.json) |
| 1,400 | 1,400 | 1,400 | 299.85 | 14.60 | **PASS** | [`JSON`](test-results/k6-catalog-1400-rps300-final.json) |
| 1,500 | 1,500 | 1,500 | 300.08 | 8.67 | **PASS** | [`JSON`](test-results/k6-catalog-1500-rps300-final.json) |
| 1,600 | 1,600 | 1,600 | 300.10 | 27.13 | **PASS** | [`JSON`](test-results/k6-catalog-1600-rps300-final.json) |
| 1,700 | 1,700 | 1,700 | 299.71 | 10.41 | **PASS** | [`JSON`](test-results/k6-catalog-1700-rps300-final.json) |
| 1,800 | 1,800 | 1,800 | 299.73 | 55.29 | **PASS** | [`JSON`](test-results/k6-catalog-1800-rps300-final.json) |
| 1,900 | 1,900 | 1,900 | 299.59 | 28.65 | **PASS** | [`JSON`](test-results/k6-catalog-1900-rps300-final.json) |
| 2,000 | 2,000 | 2,000 | 299.96 | 14.90 | **PASS** | [`JSON`](test-results/k6-catalog-2000-rps300-final.json) |

**Highest level:** 2,000/2,000 HTTP 200, **299.96 RPS**, **P95 14.90 ms**, average `http_req_duration` 7.82 ms, maximum 75.32 ms and 0 failed requests. The test completed in approximately 6.7 seconds.

**Interpretation:** The 2,000 VUs are configured k6 virtual users each completing one iteration. With the 300-RPS limiter, the 2,000 requests are spread over time. This is **not** proof of 2,000 simultaneously active HTTP connections. k6 `http_req_duration` also excludes connection-establishment phases, so its latency is not numerically interchangeable with the Python tester's latency metric.

## 5. Combined Verification Summary

| Verification | Final reported outcome |
|---|---|
| Python concurrency/request-volume levels | 23 PASS; 21,080/21,080 successful responses |
| Python 2,000-concurrency stage | 2,000/2,000 HTTP 200; P95 2,157.45 ms; recovery health PASS |
| k6 rate-limited levels (400–2,000) | 17 PASS; 20,400/20,400 successful responses |
| k6 2,000-VU/2,000-request stage | 2,000/2,000 HTTP 200; observed throughput 299.96 RPS; P95 14.90 ms |
| Response correctness | 100% HTTP 200 for all listed selected final runs |
| P95 latency acceptance | All selected final runs meet the 2,500 ms target |

Totals within each tool family count distinct test runs; they are **not** unique users and are not combined into one simultaneous-load claim. JSON evidence files in the archive must be placed into the repository's `test-results/` directory for the relative Markdown links to resolve.

## 6. Scope and Final Conclusion

**PASS — Read-only Product Catalog API load and stress verification under the documented local non-production configurations.** The selected Python runs verify successful catalog responses through a 2,000-request concurrency stage, while the separate k6 runs verify reliable request handling at approximately 300 RPS through a 2,000-request workload. Both meet the defined per-run success and P95 thresholds.

This report does not assert production-scale shopper concurrency or sustained multi-minute throughput. Purchase transaction integrity, overselling prevention, payment callbacks, and frontend lazy-loading behavior have separate acceptance and performance evidence.

**Author:** Yongky
