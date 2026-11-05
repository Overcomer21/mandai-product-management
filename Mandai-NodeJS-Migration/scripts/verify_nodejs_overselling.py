#!/usr/bin/env python3
"""Node.js MandaiDB overselling integration retest (Python stdlib only).

Creates ONE new active 'Tests' product via authenticated admin API and submits
independent customer purchases concurrently. Persists order records as evidence.
Does NOT call Stripe, cancel, restore inventory, DELETE, or update existing products.
"""
import argparse
import concurrent.futures
import datetime as datetime
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from collections import Counter

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base-url', default='http://127.0.0.1:51872')
parser.add_argument('--attempts', type=int, default=1000)
parser.add_argument('--stock', type=int, default=29)
parser.add_argument('--workers', type=int, default=60)
parser.add_argument('--confirm', required=True, help='Required: I_ACCEPT_DISPOSABLE_MANDAIDB_WRITES')
parser.add_argument('--out', default='nodejs-overselling-evidence.json')
a = parser.parse_args()
if a.confirm != 'I_ACCEPT_DISPOSABLE_MANDAIDB_WRITES':
    parser.error('Explicit disposable MandaiDB write approval is required')
u = urllib.parse.urlsplit(a.base_url)
if u.hostname not in ('localhost', '127.0.0.1') or u.scheme != 'http' or u.username or u.password:
    parser.error('Write test restricted to local HTTP gateway')
if not 2 <= a.attempts <= 3000 or not 1 <= a.stock < a.attempts or not 1 <= a.workers <= 100:
    parser.error('Expected 2<=attempts<=3000, 1<=stock<attempts, 1<=workers<=100')
BASE = a.base_url.rstrip('/')
RUN = uuid.uuid4().hex[:12]
OUT = Path(a.out)
E = {
    'test': 'AC07/AC08 live SQL concurrency / no overselling',
    'backend': 'Mandai Node.js API / MandaiDB',
    'execution_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'gateway': BASE,
    'run_id': RUN,
    'result': 'ERROR',
    'parameters': {'attempts': a.attempts, 'initial_stock': a.stock, 'max_workers': a.workers},
    'product_id': None,
    'observations': {},
    'order_ids': [],
    'failure_detail': '',
    'scope': 'Only overselling. No Stripe, cancellations, inventory restoration or existing product mutation.'
}

def http(method, route, *, token=None, payload=None, key=None, timeout=90):
    headers = {'Accept': 'application/json'}
    if token: headers['Authorization'] = 'Bearer ' + token
    if key: headers['Idempotency-Key'] = key
    body = None
    if payload is not None:
        body = json.dumps(payload).encode('utf-8')
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(BASE + route, headers=headers, data=body, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            status, raw = r.status, r.read(1000000)
    except urllib.error.HTTPError as exc:
        status, raw = exc.code, exc.read(1000000)
    try: parsed = json.loads(raw) if raw else None
    except (ValueError, UnicodeDecodeError): parsed = {'_unparseable_response': True}
    return status, parsed

def must(method, route, code, **kw):
    got, data = http(method, route, **kw)
    if got != code:
        detail = data.get('detail') if isinstance(data, dict) else str(data)[:200]
        raise AssertionError(f'{method} {route} expected HTTP {code}, got {got}: {detail}')
    return data

def login(role):
    email = os.environ.get('MANDAI_' + role + '_EMAIL')
    password = os.environ.get('MANDAI_' + role + '_PASSWORD')
    if not email or not password:
        raise RuntimeError('Missing MANDAI_' + role + '_EMAIL or MANDAI_' + role + '_PASSWORD')
    data = must('POST', '/api/auth/login', 200, payload={'email': email, 'password': password})
    token = data.get('access_token') or data.get('token')
    if not isinstance(token, str) or not token:
        raise AssertionError(role + ' login did not return a bearer token')
    return token

def report():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(E, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    md = OUT.with_suffix('.md')
    obs = E['observations']
    rows = [
        '# Mandai Node.js — Overselling Concurrency Retest Evidence', '',
        f'**Result:** {E["result"]}',
        '**Acceptance:** AC07 / AC08',
        '**Target:** Running Node.js gateway and SQL Server MandaiDB',
        f'**Raw results:** [{OUT.name}]({OUT.name})', '',
        '| Metric | Observed |', '|---|---:|',
        f'| Product ID (new disposable Tests product) | {E["product_id"] or "not created"} |',
        f'| Active product verified | {obs.get("active_product_verified", "not verified")} |',
        f'| Initial stock | {a.stock} |',
        f'| Submitted attempts | {obs.get("attempts_completed", 0)} / {a.attempts} |',
        f'| HTTP 201 (orders created) | {obs.get("successful_orders", "not measured")} |',
        f'| HTTP 409 (rejected) | {obs.get("rejected_requests", "not measured")} |',
        f'| Unexpected responses / transport errors | {obs.get("unexpected_results", "not measured")} |',
        f'| Distinct successful order IDs | {obs.get("unique_order_ids", "not measured")} |',
        f'| Ending stock | {obs.get("ending_stock", "not measured")} |',
        f'| Elapsed seconds | {obs.get("elapsed_seconds", "not measured")} |', '',
        '**Assertion:** PASS requires exactly one accepted unit per available item, '
        'the remaining attempts rejected, all order IDs unique, zero unexpected '
        'responses, ending inventory zero, and the test product still active.', '',
        '**Scope:** No Stripe API, no cancellation, no stock restoration and no DELETE. '
        'Previously executed cancellation/restoration tests are separate historical evidence.',
        '**Data preservation:** This test creates one active Tests-category product and '
        'purchase/order records. Those records remain in MandaiDB for audit. '
        'Products referenced by orders must not be deleted.', '',
    ]
    if E['failure_detail']:
        rows += ['**Failure/error details:** ' + E['failure_detail'], '']
    md.write_text('\n'.join(rows), encoding='utf-8')
    print(f'RESULT: {E["result"]}; EVIDENCE: {OUT}, {md}')

try:
    admin = login('ADMIN')
    customer = login('CUSTOMER')
    must('GET', '/health', 200)
    payload = {'name': 'AC-OVERSELL-' + RUN,
               'description': 'Disposable Node.js overselling integration evidence',
               'category': 'Tests', 'price': 1.25, 'stock': a.stock,
               'is_active': True, 'image_url': '', 'spin_image_urls': ''}
    product = must('POST', '/api/admin/products', 201, token=admin, payload=payload)
    pid = product.get('id', product.get('product_id'))
    if not isinstance(pid, int) or pid <= 0:
        raise AssertionError('Could not determine created product id')
    E['product_id'] = pid
    before = must('GET', f'/api/admin/products/{pid}', 200, token=admin)
    if before.get('is_active') is not True or int(before.get('stock', -1)) != a.stock:
        raise AssertionError('Newly created product is not active with expected initial stock')
    E['observations']['active_product_verified'] = True
    print(f'Created ACTIVE Tests product {pid} with stock {a.stock}; submitting {a.attempts} purchases')

    def purchase(i):
        # Every attempt has its own idempotency key: independent buyers/requests.
        key = f'ac-oversell-{RUN}-{i}-{uuid.uuid4().hex[:16]}'
        try:
            code, data = http('POST', '/api/purchases', token=customer,
                              payload={'product_id': pid, 'quantity': 1}, key=key)
            if code == 201:
                order_id = data.get('order_id') if isinstance(data, dict) else None
                return {'status': code, 'order_id': order_id}
            if code == 409:
                return {'status': code, 'detail': str(data.get('detail', ''))[:150] if isinstance(data, dict) else ''}
            return {'status': code, 'response': str(data)[:150]}
        except Exception as exc:
            return {'status': 'TRANSPORT_ERROR', 'error': type(exc).__name__ + ': ' + str(exc)[:120]}

    begin = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as pool:
        results = list(pool.map(purchase, range(a.attempts)))
    duration = round(time.monotonic() - begin, 3)
    freq = Counter(str(x['status']) for x in results)
    wins = [x['order_id'] for x in results if x['status'] == 201]
    reject_details = Counter(x.get('detail', '') for x in results if x['status'] == 409)
    unexpected = [x for x in results if x['status'] not in (201, 409)]
    # Full result counts always written; never claim PASS on unexpected/ambiguous outcomes.
    after = must('GET', f'/api/admin/products/{pid}', 200, token=admin)
    obs = E['observations']
    obs.update({
        'attempts_completed': len(results),
        'successful_orders': freq['201'],
        'rejected_requests': freq['409'],
        'unexpected_results': len(unexpected),
        'unexpected_examples': unexpected[:10],
        'http_status_counts': dict(freq),
        'rejection_reason_counts': dict(reject_details),
        'unique_order_ids': len(set(x for x in wins if isinstance(x, int))),
        'ending_stock': after.get('stock'),
        'active_after_test': after.get('is_active'),
        'elapsed_seconds': duration,
    })
    E['order_ids'] = [x for x in wins if isinstance(x, int)]
    checks = [
        len(results) == a.attempts,
        freq['201'] == a.stock,
        freq['409'] == a.attempts-a.stock,
        not unexpected,
        len(wins) == a.stock and len(E['order_ids']) == a.stock,
        len(set(E['order_ids'])) == a.stock,
        freq['409'] > 0 and all('insufficient stock' in x.lower() for x in reject_details.keys()),
        int(after.get('stock', -1)) == 0,
        after.get('is_active') is True,
    ]
    if not all(checks):
        E['result'] = 'FAIL'
        E['failure_detail'] = 'Observed values did not meet all overselling invariants. Inspect the JSON report and database before retrying.'
    else:
        E['result'] = 'PASS'
    print(f'HTTP 201={freq["201"]}; HTTP 409={freq["409"]}; unexpected={len(unexpected)}; ending_stock={after.get("stock")}; unique_orders={obs["unique_order_ids"]}')
except Exception as ex:
    E['result'] = 'ERROR'
    E['failure_detail'] = type(ex).__name__ + ': ' + str(ex)[:500]
    print('[ERROR]', E['failure_detail'])
finally:
    report()
sys.exit(0 if E['result'] == 'PASS' else 1)
