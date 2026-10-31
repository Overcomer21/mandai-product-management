"""Read-only concurrent load test for Mandai product catalog.

Example:
    python scripts/test_catalog_concurrency.py --users 500 --requests 1000
"""
import argparse
import asyncio
import json
import statistics
import time
from collections import Counter
from pathlib import Path

import httpx


def parse_args():
    parser = argparse.ArgumentParser(description='Read-only product catalog load test')
    parser.add_argument('--url', default='http://127.0.0.1:8000/api/products?limit=20&offset=0')
    parser.add_argument('--users', type=int, default=500)
    parser.add_argument('--requests', type=int, default=1000)
    parser.add_argument('--timeout', type=float, default=30)
    parser.add_argument('--expected-count', type=int, default=20)
    parser.add_argument('--output', default='test-results/catalog-concurrency-500-users.json')
    args = parser.parse_args()
    if args.users < 1 or args.requests < 1 or args.timeout <= 0 or args.expected_count < 0:
        parser.error('users, requests, timeout must be positive; expected-count cannot be negative')
    return args


def percentile(values, fraction):
    return values[min(len(values) - 1, int((len(values) - 1) * fraction))]


async def run(args):
    semaphore = asyncio.Semaphore(args.users)
    limits = httpx.Limits(max_connections=args.users, max_keepalive_connections=args.users)
    async with httpx.AsyncClient(timeout=httpx.Timeout(args.timeout), limits=limits, trust_env=False) as client:
        async def request_one(index):
            async with semaphore:
                start = time.perf_counter()
                try:
                    response = await client.get(args.url)
                    duration = (time.perf_counter() - start) * 1000
                    if response.status_code != 200:
                        return {'index': index, 'status': str(response.status_code), 'latency_ms': duration,
                                'detail': response.text[:300]}
                    try:
                        data = response.json()
                    except ValueError as exc:
                        return {'index': index, 'status': 'INVALID_JSON', 'latency_ms': duration,
                                'detail': str(exc)}
                    if not isinstance(data, list) or len(data) != args.expected_count:
                        return {'index': index, 'status': 'INVALID_RESPONSE', 'latency_ms': duration,
                                'detail': f'Expected {args.expected_count} products; got {len(data) if isinstance(data, list) else type(data).__name__}'}
                    return {'index': index, 'status': '200', 'latency_ms': duration}
                except Exception as exc:
                    duration = (time.perf_counter() - start) * 1000
                    detail = f'{type(exc).__name__}: {exc!s}'
                    print(f'REQUEST FAILED index={index} type={type(exc).__name__} '
                          f'message={str(exc)!r} duration={duration:.2f}ms', flush=True)
                    return {'index': index, 'status': type(exc).__name__,
                            'latency_ms': duration, 'detail': detail}

        started = time.perf_counter()
        results = await asyncio.gather(*(request_one(i) for i in range(args.requests)))
        elapsed = time.perf_counter() - started

    codes = Counter(item['status'] for item in results)
    latencies = sorted(item['latency_ms'] for item in results)
    successes = codes['200']
    failures = [item for item in results if item['status'] != '200']
    summary = {
        'endpoint': args.url, 'max_concurrent_requests': args.users,
        'total_requests': args.requests, 'success': successes,
        'errors': len(failures), 'elapsed_seconds': round(elapsed, 3),
        'throughput_rps': round(args.requests / elapsed, 2),
        'average_latency_ms': round(statistics.mean(latencies), 2),
        'p95_latency_ms': round(percentile(latencies, .95), 2),
        'p99_latency_ms': round(percentile(latencies, .99), 2),
        'response_statuses': dict(codes), 'result': 'PASS' if not failures else 'FAIL',
        'failures': failures,
    }
    print('\n=== PRODUCT CATALOG CONCURRENCY TEST ===')
    for label, key in [
        ('Endpoint', 'endpoint'), ('Concurrent users (max)', 'max_concurrent_requests'),
        ('Total requests', 'total_requests'), ('Success', 'success'),
        ('Errors', 'errors'), ('Throughput (RPS)', 'throughput_rps'),
        ('Average latency (ms)', 'average_latency_ms'), ('P95 latency (ms)', 'p95_latency_ms'),
        ('P99 latency (ms)', 'p99_latency_ms'), ('Response statuses', 'response_statuses'),
        ('RESULT', 'result'),
    ]:
        value = summary[key]
        if key == 'success':
            value = f'{value}/{args.requests}'
        print(f'{label:23}: {value}')
    path = Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print(f'Report saved to         : {path.resolve()}')


if __name__ == '__main__':
    asyncio.run(run(parse_args()))
