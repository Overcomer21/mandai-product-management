"""Read-only Mandai API load/stress test. Python 3.10+, standard library only.

Default local-only and endpoints /health, /api/products. Never creates orders,
checkout sessions, or invokes webhooks. Run only on environments you own.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
import json
import math
import statistics
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

@dataclass
class Outcome:
    status: int
    elapsed_ms: float
    error: str = ""


def request_once(url: str, timeout: float, token: str) -> Outcome:
    headers = {"Accept": "application/json", "User-Agent": "MandaiReadOnlyStressTest/1.0"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    start = time.perf_counter()
    try:
        with urlopen(Request(url, headers=headers, method="GET"), timeout=timeout) as response:
            response.read()  # measure full response transfer
            return Outcome(response.status, (time.perf_counter() - start) * 1000)
    except HTTPError as ex:
        return Outcome(ex.code, (time.perf_counter() - start) * 1000, f"HTTP {ex.code}")
    except (URLError, TimeoutError, OSError) as ex:
        return Outcome(0, (time.perf_counter() - start) * 1000, str(ex)[:160])


def pct(values, q):
    if not values:
        return None
    ordered = sorted(values)
    pos = (len(ordered) - 1) * q
    lo = math.floor(pos)
    hi = math.ceil(pos)
    return round(ordered[lo] + (ordered[hi] - ordered[lo]) * (pos - lo), 2)


def run_stage(url: str, concurrency: int, requests: int, timeout: float, token: str):
    started = time.perf_counter()
    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(request_once, url, timeout, token) for _ in range(requests)]
        outcomes = [future.result() for future in as_completed(futures)]
    duration = time.perf_counter() - started
    success = [o for o in outcomes if 200 <= o.status < 300]
    errors = [o for o in outcomes if not 200 <= o.status < 300]
    latencies = [o.elapsed_ms for o in outcomes]
    status_counts = {}
    for item in outcomes:
        k = str(item.status) if item.status else "network_error"
        status_counts[k] = status_counts.get(k, 0) + 1
    return {
        "concurrency": concurrency,
        "requests": requests,
        "success": len(success),
        "errors": len(errors),
        "error_rate_pct": round(100 * len(errors) / len(outcomes), 2),
        "elapsed_s": round(duration, 2),
        "throughput_rps": round(len(outcomes) / duration, 2),
        "latency_ms": {"p50": pct(latencies, 0.5), "p95": pct(latencies, 0.95), "p99": pct(latencies, 0.99), "max": round(max(latencies), 2)},
        "http_statuses": status_counts,
        "error_samples": list(dict.fromkeys(o.error for o in errors if o.error))[:5]
    }


def main():
    parser = argparse.ArgumentParser(description="Mandai API read-only local stress test")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--endpoint", choices=["/health", "/api/products", "/api/orders/my"], default="/api/products")
    parser.add_argument("--token", default="", help="Bearer token for /api/orders/my; do not share captured output containing secrets")
    parser.add_argument("--levels", default="5,10,20,50,100", help="Comma-separated concurrent worker counts")
    parser.add_argument("--requests-per-level", type=int, default=200)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--max-error-rate", type=float, default=1.0, help="PASS threshold, percent")
    parser.add_argument("--max-p95-ms", type=float, default=2000.0, help="PASS threshold, milliseconds")
    parser.add_argument("--output", default="mandai-stress-results.json")
    args = parser.parse_args()

    parsed = urlparse(args.base_url)
    if parsed.scheme != "http" or parsed.hostname not in {"localhost", "127.0.0.1"} or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in {"", "/"}:
        parser.error("Only local HTTP base URLs are permitted (http://localhost:PORT or http://127.0.0.1:PORT)")
    if args.endpoint == "/api/orders/my" and not args.token:
        parser.error("--token is required for /api/orders/my")
    try:
        levels = [int(x.strip()) for x in args.levels.split(",")]
    except ValueError:
        parser.error("--levels must contain integers")
    if not levels or any(level < 1 or level > 200 for level in levels):
        parser.error("Each concurrency level must be between 1 and 200")
    if not 1 <= args.requests_per_level <= 10000 or not 0.1 <= args.timeout <= 60:
        parser.error("Requests per level must be 1..10000 and timeout 0.1..60 seconds")

    url = args.base_url.rstrip("/") + args.endpoint
    print(f"Target: {url} [READ ONLY] | levels: {levels} | requests/stage: {args.requests_per_level}")
    results = []
    for level in levels:
        stage = run_stage(url, level, args.requests_per_level, args.timeout, args.token)
        stage["pass"] = stage["error_rate_pct"] <= args.max_error_rate and stage["latency_ms"]["p95"] <= args.max_p95_ms
        results.append(stage)
        print(f"Users={level:>3} ok={stage['success']:>4}/{stage['requests']} errors={stage['errors']:>3} "
              f"RPS={stage['throughput_rps']:>7} p95={stage['latency_ms']['p95']:>7}ms "
              f"p99={stage['latency_ms']['p99']:>7}ms {'PASS' if stage['pass'] else 'FAIL'}")
        if not stage["pass"]:
            print("Threshold breached: stopping escalation to protect the development API.")
            break
    # Recovery verification after load
    recovery = request_once(args.base_url.rstrip("/") + "/health", args.timeout, "")
    recovery_ok = 200 <= recovery.status < 300
    report = {
        "target": url, "endpoint": args.endpoint, "thresholds": {"max_error_rate_pct": args.max_error_rate, "max_p95_ms": args.max_p95_ms},
        "stages": results, "recovery_health": {"status": recovery.status, "latency_ms": round(recovery.elapsed_ms, 2), "pass": recovery_ok},
        "overall_pass": all(stage["pass"] for stage in results) and len(results) == len(levels) and recovery_ok,
        "notes": "Read-only test. Does not validate payment writes, webhook idempotency, SQL Server transaction concurrency, or Stripe provider capacity."
    }
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
    print(f"Recovery /health HTTP {recovery.status}: {'PASS' if recovery_ok else 'FAIL'}")
    print(f"Overall: {'PASS' if report['overall_pass'] else 'FAIL / NOT COMPLETED'}; report: {args.output}")
    raise SystemExit(0 if report["overall_pass"] else 1)

if __name__ == "__main__":
    main()
