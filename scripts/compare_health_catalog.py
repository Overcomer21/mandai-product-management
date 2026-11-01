import asyncio
import json
import statistics
import time
from pathlib import Path

import httpx

BASE_URL = ""
USERS = 50
REQUESTS = 200
LIMIT = 10
TIMEOUT = 60

def percentile(values, fraction):
    values = sorted(values)
    return values[min(len(values) - 1, int((len(values) - 1) * fraction))]

async def benchmark(client, endpoint, expected_type, users):
    semaphore = asyncio.Semaphore(users)
    latencies = []
    statuses = []

    async def request_one():
        async with semaphore:
            start = time.perf_counter()
            try:
                response = await client.get(endpoint)
                elapsed = (time.perf_counter() - start) * 1000
                data = response.json()

                valid = response.status_code == 200

                if expected_type == "health":
                    valid = valid and isinstance(data, dict) and data.get("status") == "ok"
                else:
                    valid = valid and isinstance(data, list) and len(data) == LIMIT

                latencies.append(elapsed)
                statuses.append("200" if valid else f"INVALID_{response.status_code}")

            except Exception as exc:
                latencies.append((time.perf_counter() - start) * 1000)
                statuses.append(type(exc).__name__)

    # Warm-up: exclude initial connection establishment from measurements.
    for _ in range(10):
        try:
            await client.get(endpoint)
        except Exception:
            pass

    started = time.perf_counter()
    await asyncio.gather(*(request_one() for _ in range(REQUESTS)))
    elapsed = time.perf_counter() - started

    successful = statuses.count("200")

    return {
        "endpoint": endpoint,
        "concurrent_users": users,
        "requests": REQUESTS,
        "success": successful,
        "errors": REQUESTS - successful,
        "elapsed_seconds": round(elapsed, 3),
        "throughput_rps": round(REQUESTS / elapsed, 2),
        "average_latency_ms": round(statistics.mean(latencies), 2),
        "p95_latency_ms": round(percentile(latencies, 0.95), 2),
        "p99_latency_ms": round(percentile(latencies, 0.99), 2),
        "statuses": {s: statuses.count(s) for s in set(statuses)}
    }

async def main():
    global BASE_URL

    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--users", type=int, default=50)
    parser.add_argument("--requests", type=int, default=200)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    BASE_URL = args.base_url.rstrip("/")

    global REQUESTS
    REQUESTS = args.requests

    limits = httpx.Limits(
        max_connections=args.users,
        max_keepalive_connections=args.users
    )

    async with httpx.AsyncClient(
        timeout=httpx.Timeout(TIMEOUT),
        limits=limits,
        trust_env=False
    ) as client:

        results = []

        for name, path, kind in [
            ("HEALTH", "/health", "health"),
            ("PRODUCT CATALOG", f"/api/products?limit={LIMIT}&offset=0", "catalog")
        ]:
            print(f"\n=== {name}: {args.users} USERS ===")
            result = await benchmark(
                client, BASE_URL + path, kind, args.users
            )
            results.append(result)

            for key, value in result.items():
                print(f"{key:24}: {value}")

        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(
            json.dumps(results, indent=2),
            encoding="utf-8"
        )
        print(f"\nReport saved: {args.output}")

if __name__ == "__main__":
    asyncio.run(main())
