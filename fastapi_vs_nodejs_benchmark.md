# FastAPI vs Node.js — Catalog API Benchmark

**Test date:** 5 November 2026  
**Test tool:** Python `mandai_stress_test.py` (read-only burst concurrency; K6 results excluded)  
**Endpoint:** `GET /api/products`  
**Deployment:** Docker, isolated networks, NGINX gateways. FastAPI: `127.0.0.1:52001`; Node.js: `127.0.0.1:51872`.

## Overall Summary

| Metric | FastAPI Docker | Node.js Docker |
|---|---:|---:|
| Concurrency levels passed | 23/23 | 23/23 |
| Total successful requests | 17,435 / 17,435 | 17,435 / 17,435 |
| HTTP errors | 0 | 0 |
| Peak throughput | **1,105.07 RPS** (1,900 users) | 995.36 RPS (1,400 users) |
| RPS at 2,000 users | **1,042.74** | 991.78 |
| P95 at 2,000 users | **117.56 ms** | 121.95 ms |
| P99 at 2,000 users | **155.05 ms** | 178.43 ms |
| Higher throughput across levels | **19/23** | 4/23 |
| Lower P95 across levels | **17/23** | 6/23 |

## Results by Concurrent Users

Higher **RPS** is better; lower **P95 latency** is better. Winner columns assess each metric separately, not an overall winner for that level.

| Concurrent users | FastAPI RPS | Node.js RPS | Faster throughput | FastAPI P95 (ms) | Node.js P95 (ms) | Lower latency |
|---:|---:|---:|---|---:|---:|---|
| 10 | 14.51 | 14.04 | **FastAPI** | 609.65 | 699.63 | **FastAPI** |
| 20 | 52.79 | 65.86 | **Node.js** | 368.06 | 297.81 | **Node.js** |
| 30 | 83.68 | 96.13 | **Node.js** | 311.72 | 288.94 | **Node.js** |
| 50 | 116.44 | 106.01 | **FastAPI** | 371.76 | 436.61 | **FastAPI** |
| 75 | 249.12 | 180.16 | **FastAPI** | 256.25 | 361.03 | **FastAPI** |
| 100 | 193.83 | 411.44 | **Node.js** | 448.74 | 33.17 | **Node.js** |
| 150 | 467.97 | 384.52 | **FastAPI** | 49.47 | 98.02 | **FastAPI** |
| 200 | 396.86 | 334.35 | **FastAPI** | 52.96 | 98.38 | **FastAPI** |
| 300 | 548.33 | 442.23 | **FastAPI** | 64.31 | 66.11 | **FastAPI** |
| 400 | 816.62 | 564.05 | **FastAPI** | 36.57 | 91.40 | **FastAPI** |
| 500 | 817.27 | 504.30 | **FastAPI** | 49.86 | 135.84 | **FastAPI** |
| 600 | 768.60 | 609.90 | **FastAPI** | 57.02 | 87.23 | **FastAPI** |
| 700 | 827.87 | 774.05 | **FastAPI** | 68.18 | 75.04 | **FastAPI** |
| 800 | 793.26 | 780.60 | **FastAPI** | 86.70 | 77.13 | **Node.js** |
| 900 | 859.38 | 816.61 | **FastAPI** | 80.57 | 65.15 | **Node.js** |
| 1,000 | 909.14 | 879.28 | **FastAPI** | 78.80 | 96.84 | **FastAPI** |
| 1,200 | 966.67 | 865.86 | **FastAPI** | 86.98 | 116.72 | **FastAPI** |
| 1,400 | 969.39 | 995.36 | **Node.js** | 115.87 | 79.84 | **Node.js** |
| 1,600 | 1,016.82 | 915.54 | **FastAPI** | 104.50 | 109.89 | **FastAPI** |
| 1,700 | 1,084.63 | 904.65 | **FastAPI** | 104.40 | 143.24 | **FastAPI** |
| 1,800 | 1,000.03 | 961.20 | **FastAPI** | 105.58 | 129.11 | **FastAPI** |
| 1,900 | 1,105.07 | 966.49 | **FastAPI** | 97.07 | 127.88 | **FastAPI** |
| 2,000 | 1,042.74 | 991.78 | **FastAPI** | 117.56 | 121.95 | **FastAPI** |

## Conclusion

Both deployments passed **all 23 Python benchmark levels**, each processing **17,435 successful requests with zero HTTP errors**. FastAPI delivered higher throughput at **19/23** levels and lower P95 latency at **17/23** levels. For example, at **10 users**, FastAPI achieved **14.51 RPS versus 14.04 RPS** and **609.65 ms versus 699.63 ms P95**; FastAPI was better on both measures. At **100 users**, however, Node.js was faster on both measures (**411.44 vs 193.83 RPS**; **33.17 vs 448.74 ms P95**). At **2,000 users**, FastAPI led by about **5.1% in throughput** and had approximately **3.6% lower P95 latency**.

**Method and limits:** Each level issues one GET per concurrent worker; requests timeout after 30 seconds, with a 0% error-rate threshold and P95 limit of 2,500 ms. Tests ran sequentially, so measurements can vary with host load, cache state, and resource allocation. These numbers compare the **tested configurations**, not language-level performance in general. Separate K6 burst tests encountered TCP connection failures; those results are **not included** in this Python performance table and remain an unresolved reliability finding.
