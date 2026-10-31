# Mandai E-Merchandise â€” Product Catalog API Gradual Ramp-Up Load Test Report

**Assessment:** Mandai Wildlife Group â€” Question 5, Full-Stack Product Management
**Test scope:** Read-only Product Catalog API load and performance testing
**Environment:** Local Development and Test Environment (Non-Production)
**Primary benchmark:** Gradual ramp-up to 700 concurrent virtual users (VUs)
**Overall result:** **PASS â€” 3 gradual ramp-up scenarios (300, 500, and 700 VUs)**
**Author:** Yongky

## 1. Objective

Evaluate Product Catalog API reliability, response correctness, throughput, and latency under concurrent HTTP traffic routed through an NGINX load balancer to five FastAPI/Uvicorn backend instances.

## 2. Test Environment

The tests were conducted in a **Local Development and Test Environment (Non-Production)** on a **Windows-based development laptop**. NGINX, hosted in Docker Desktop, distributed incoming requests across five locally hosted FastAPI/Uvicorn backend instances. Grafana k6 generated the concurrent HTTP workload, and Microsoft SQL Server supported application data storage.

| Component | Configuration |
|---|---|
| Host | Windows-based development laptop |
| Environment classification | Local Development and Test Environment (Non-Production) |
| Load-testing tool | Grafana k6 |
| Load balancer | NGINX (Docker Desktop) |
| Backend | 5 FastAPI/Uvicorn instances (ports 8000â€“8004) |
| Database | Microsoft SQL Server (`MandaiDB`) |
| HTTP request | `GET /api/products?limit=10&offset=0` |
| Data operation | Read-only; no master-data modification |
| Response checks | HTTP 200 and JSON array containing exactly 10 products |

**Measurement scope:** Virtual users are k6 clients repeatedly requesting the same catalog endpoint and pagination parameters. They are not equivalent to a verified number of shoppers interacting with the Flutter UI. Results characterize this specific local test configuration.

## 3. Test Methodology

The tests used a **gradual ramp-up** workload to increase concurrent virtual users in a controlled manner.

| Parameter | Configuration |
|---|---|
| Peak virtual-user targets | 300, 500, and 700 VUs |
| Load pattern | 0 â†’ target VUs â†’ 0 |
| Ramp-up | 30 seconds |
| Peak hold | 30 seconds |
| Ramp-down | 10 seconds |
| Scheduled duration | 70 seconds per scenario |
| Request behavior | Each VU repeatedly sends a read-only catalog GET request |

**Metric interpretation:** Total requests, average throughput (RPS), and response-time percentiles are measured across the entire 70-second run, including ramp-up, peak hold, and ramp-downâ€”not solely the peak-hold period.

## 4. Test Results

### 4.1 Gradual Ramp-Up Load Testing â€” 300 to 700 VUs

| Peak VUs | Total HTTP Requests | Failed Requests | HTTP Success Rate | Response Checks | Average Latency | P95 Latency | Average Throughput | Result |
|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 300 | 30,404 | 0 | 100% | 100% | 494.14 ms | 1.11 s | 434.26 RPS | **PASS** |
| 500 | 31,763 | 0 | 100% | 100% | 790.98 ms | 1.53 s | 453.63 RPS | **PASS** |
| **700** | **27,691** | **0** | **100%** | **100% (55,382/55,382)** | **1.27 s** | **2.45 s** | **395.52 RPS** | **PASS** |

*Metrics are taken from the recorded k6 test summaries. The referenced JSON evidence files provide the corresponding machine-readable results.*

## 5. Evaluation Criteria

| Criterion | Reported outcome | Assessment |
|---|---|---|
| HTTP request failures | 0 in all three reported ramp-up scenarios | **PASS** |
| Product Catalog response checks | 100% in the reported ramp-up scenarios | **PASS** |
| 700-VU P95 response time | 2.45 seconds | **PASS â€” within internal 3.5-second target** |
| Highest reported ramp-up concurrency | 700 VUs | **PASS** |

**Target definition:** **P95 â‰¤ 3.5 seconds** is an internally selected performance benchmark, not an official latency SLA supplied by Mandai. The benchmark is evaluated against the 700-VU gradual ramp-up run. Other metrics are reported as measured observations.

## 6. Test Evidence

Evidence paths below are relative to this Markdown file at the **GitHub repository root**. The referenced JSON evidence files should be committed alongside this report for the links to resolve.

### 6.1 Gradual Ramp-Up Evidence

| Scenario | k6 JSON Evidence |
|---|---|
| 300 VUs | [`test-results/k6-catalog-300-ramp.json`](test-results/k6-catalog-300-ramp.json) |
| 500 VUs | [`test-results/k6-catalog-500-ramp-final.json`](test-results/k6-catalog-500-ramp-final.json) |
| **700 VUs (primary benchmark)** | **[`test-results/k6-catalog-700-ramp-final.json`](test-results/k6-catalog-700-ramp-final.json)** |

### 6.2 Evidence Verification

From the repository root, confirm the three selected evidence files exist:

```powershell
$evidence = @(
  'k6-catalog-300-ramp.json',
  'k6-catalog-500-ramp-final.json',
  'k6-catalog-700-ramp-final.json'
)
$evidence | ForEach-Object {
  [PSCustomObject]@{
    File = $_
    Exists = Test-Path (Join-Path '.\test-results' $_)
  }
}
```

To inspect the primary benchmark summary:

```powershell
$report = Get-Content '.\test-results\k6-catalog-700-ramp-final.json' -Raw | ConvertFrom-Json
$report.metrics.http_reqs
$report.metrics.http_req_failed
$report.metrics.http_req_duration
$report.metrics.checks
```

## 7. Test Findings and Scope

- **Three gradual ramp-up scenarios (300, 500, and 700 VUs)** completed with zero HTTP request failures and 100% response checks.
- At the **700-VU** peak, the Product Catalog API processed **27,691 HTTP requests**, with **395.52 average RPS** and **P95 response time of 2.45 seconds** across the 70-second run.
- The 700-VU P95 result was within the internally selected **3.5-second** benchmark.
- The results apply to **read-only Product Catalog API operations** in the documented local non-production environment. Frontend rendering, login, checkout, and payment performance require separate workload-specific measurements.

## 8. Conclusion

**PASS â€” Product Catalog API Gradual Ramp-Up Load Testing (3 scenarios, up to 700 concurrent VUs).**

The three reported gradual ramp-up tests demonstrated successful Product Catalog API responses with **zero HTTP request failures**. The primary **700-VU gradual ramp-up benchmark** completed **27,691 requests**, with **100% response validation**, **395.52 average requests per second**, and **2.45-second P95 latency**. These results met the documented API reliability and response correctness criteria and the internally selected 3.5-second P95 benchmark for the 700-VU scenario.

---

**Author:** Yongky
