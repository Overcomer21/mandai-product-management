#!/usr/bin/env python3
"""Black-box Node.js Mandai API acceptance checks. Standard library only.
Default: GETs, invalid requests and authorization-denial probes only.
Explicit opt-in: creates/deactivates disposable test products and test orders.
Never deletes existing data or manipulates Stripe/SQL directly.
"""
import argparse
import concurrent.futures
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

P = argparse.ArgumentParser(description=__doc__)
P.add_argument('--base-url', default='http://127.0.0.1:51872')
P.add_argument('--allow-disposable-writes', action='store_true', help='Enable REAL SQL-changing API requests using newly created Tests-category products. Leaves audit/order records.')
P.add_argument('--confirm', default='', help='Must exactly be I_ACCEPT_DISPOSABLE_MANDAIDB_WRITES when writes enabled')
P.add_argument('--out', default='nodejs_ac_results.json')
args = P.parse_args()
if args.allow_disposable_writes and args.confirm != 'I_ACCEPT_DISPOSABLE_MANDAIDB_WRITES':
    P.error('Writes require --confirm I_ACCEPT_DISPOSABLE_MANDAIDB_WRITES; tests create persistent test order/payment history.')
BASE = args.base_url.rstrip('/')
ADMIN_EMAIL=os.getenv('MANDAI_ADMIN_EMAIL','')
ADMIN_PASSWORD=os.getenv('MANDAI_ADMIN_PASSWORD','')
CUSTOMER_EMAIL=os.getenv('MANDAI_CUSTOMER_EMAIL','')
CUSTOMER_PASSWORD=os.getenv('MANDAI_CUSTOMER_PASSWORD','')
results=[]
runid=uuid.uuid4().hex[:12]

class ApiError(Exception): pass

def api(method,path,token=None,data=None,key=None,timeout=20):
    headers={'Accept':'application/json'}
    if token:headers['Authorization']='Bearer '+token
    if key:headers['Idempotency-Key']=key
    raw=None
    if data is not None:
        headers['Content-Type']='application/json'
        raw=json.dumps(data).encode('utf-8')
    request=urllib.request.Request(BASE+path,data=raw,headers=headers,method=method)
    try:
        with urllib.request.urlopen(request,timeout=timeout) as response:
            status=response.status
            payload=response.read(2_000_000)
    except urllib.error.HTTPError as error:
        status=error.code
        payload=error.read(2_000_000)
    parsed=None
    try:parsed=json.loads(payload) if payload else None
    except (UnicodeDecodeError,json.JSONDecodeError):parsed=None
    return status,parsed

def test(ac,label,fn):
    try:
        detail=fn()
        results.append({'criterion':ac,'name':label,'status':'PASS','detail':str(detail or '')[:240]})
    except AssertionError as e:
        results.append({'criterion':ac,'name':label,'status':'FAIL','detail':str(e)[:500]})
    except Exception as e:
        results.append({'criterion':ac,'name':label,'status':'ERROR','detail':type(e).__name__+': '+str(e)[:400]})

def skip(ac,label,reason):
    results.append({'criterion':ac,'name':label,'status':'SKIP','detail':reason})

def expect_response(method,path,allowed,**kw):
    code,body=api(method,path,**kw)
    assert code in allowed, f'{method} {path}: expected {sorted(allowed)} got {code}; response={str(body)[:180]}'
    return body

def login(email,password):
    code,body=api('POST','/api/auth/login',data={'email':email,'password':password})
    assert code==200, f'login: expected 200, got {code}; {str(body)[:140]}'
    assert isinstance(body,dict), 'login response must be object'
    token=body.get('access_token') or body.get('token')
    assert isinstance(token,str) and token, 'login response lacks access_token/token'
    return token

def product_payload(stock=5,name=None):
    return {'name':name or f'AC-Node-Tests-{runid}', 'category':'Tests', 'description':'Disposable Node.js acceptance verification item', 'price':1.25, 'stock':stock,'is_active':True,'image_url':'','spin_image_urls':''}

def product_id_from(data):
    assert isinstance(data,dict),f'Expected JSON product, got {type(data).__name__}'
    x=data.get('id',data.get('product_id'))
    assert isinstance(x,int) and x>0,f'Expected numeric product id in response, fields={list(data)[:12]}'
    return x

def observed_catalog():
    body=expect_response('GET','/api/products?limit=5&offset=0', {200})
    assert isinstance(body,list),'Catalog should return JSON array'
    return len(body)

test('AC01/02/04','Gateway health',lambda: expect_response('GET','/health',{200}))
test('AC01/02/04','Public catalog list, pagination',observed_catalog)
test('AC02/04','Public categories',lambda:expect_response('GET','/api/products/categories',{200}))
test('AC02/04','Public catalog count',lambda:expect_response('GET','/api/products/count',{200}))
test('AC02/04','Invalid pagination rejected',lambda:expect_response('GET','/api/products?limit=101',{422}))
test('AC02/04','Invalid sort rejected',lambda:expect_response('GET','/api/products?sort=not-valid',{422}))
test('AC02/04','Catalog filter/sort endpoint',lambda:expect_response('GET','/api/products?limit=5&offset=0&sort=Price%20low&in_stock=true',{200}))

# Route guards: invalid POSTs intentionally have no JSON payload and cannot mutate SQL.
for method,path in [('GET','/api/admin/products'),('GET','/api/admin/products/count'),('GET','/api/admin/products/stats'),('POST','/api/admin/products'),('PUT','/api/admin/products/99999999'),('DELETE','/api/admin/products/99999999')]:
    test('AC03/05',f'Unauthenticated {method} {path} denied',lambda method=method,path=path:expect_response(method,path,{401,403}))
for method,path in [('POST','/api/purchases'),('POST','/api/checkout'),('GET','/api/orders/my')]:
    test('AC06',f'Unauthenticated {method} {path} denied',lambda method=method,path=path:expect_response(method,path,{401,403}))

admin_token=customer_token=None
if ADMIN_EMAIL and ADMIN_PASSWORD:
    def admin_auth():
        global admin_token
        admin_token=login(ADMIN_EMAIL,ADMIN_PASSWORD)
        return 'Authenticated admin token received (not printed)'
    test('AC01/03/05','Admin login',admin_auth)
else: skip('AC01/03/05','Admin login','Set MANDAI_ADMIN_EMAIL and MANDAI_ADMIN_PASSWORD')
if CUSTOMER_EMAIL and CUSTOMER_PASSWORD:
    def customer_auth():
        global customer_token
        customer_token=login(CUSTOMER_EMAIL,CUSTOMER_PASSWORD)
        return 'Authenticated customer token received (not printed)'
    test('AC01/04/06','Customer login',customer_auth)
else: skip('AC01/04/06','Customer login','Set MANDAI_CUSTOMER_EMAIL and MANDAI_CUSTOMER_PASSWORD')

if admin_token:
    test('AC03/05','Admin inventory list',lambda:expect_response('GET','/api/admin/products?limit=5',{200},token=admin_token))
    test('AC03/05','Admin inventory stats',lambda:expect_response('GET','/api/admin/products/stats',{200},token=admin_token))
    test('AC03/05','Admin invalid product create rejected',lambda:expect_response('POST','/api/admin/products',{422},token=admin_token,data={'name':'','price':-1,'stock':-1}))
    test('AC06','Admin purchase denied',lambda:expect_response('POST','/api/purchases',{403},token=admin_token,data={'product_id':99999999,'quantity':1},key='ac-admin-'+runid))
if customer_token:
    for method,path in [('GET','/api/admin/products'),('GET','/api/admin/products/count'),('GET','/api/admin/products/stats'),('POST','/api/admin/products'),('PUT','/api/admin/products/99999999'),('DELETE','/api/admin/products/99999999')]:
        test('AC03/05',f'Customer {method} {path} denied',lambda method=method,path=path:expect_response(method,path,{403},token=customer_token))
    test('AC06','Customer orders endpoint',lambda:expect_response('GET','/api/orders/my',{200},token=customer_token))
    test('AC06','Customer order detail endpoint',lambda:expect_response('GET','/api/orders/my/details',{200},token=customer_token))
    test('AC06','Invalid purchase quantity rejected',lambda:expect_response('POST','/api/purchases',{422},token=customer_token,key='ac-invalid-'+runid,data={'product_id':1,'quantity':0}))

if not args.allow_disposable_writes:
    skip('AC03/05','Real admin CRUD lifecycle','Requires --allow-disposable-writes with explicit confirmation')
    skip('AC06/07','Real purchase and idempotent replay','Requires disposable SQL writes')
    skip('AC07/08','Concurrent overselling prevention','Requires disposable SQL writes')
elif not (admin_token and customer_token):
    skip('AC03/05/06/07/08','Real CRUD, purchase and concurrency','Both admin and customer credentials are required')
else:
    created=[]
    def create_disposable(stock,name):
        resp=expect_response('POST','/api/admin/products',{201},token=admin_token,data=product_payload(stock,name))
        pid=product_id_from(resp)
        created.append(pid)
        return pid
    def crud():
        pid=create_disposable(2,f'AC-CRUD-{runid}')
        got=expect_response('GET',f'/api/admin/products/{pid}',{200},token=admin_token)
        assert isinstance(got,dict),'GET admin product must return object'
        changed=product_payload(3,f'AC-CRUD-Updated-{runid}')
        expect_response('PUT',f'/api/admin/products/{pid}',{200},token=admin_token,data=changed)
        got=expect_response('GET',f'/api/admin/products/{pid}',{200},token=admin_token)
        assert got.get('name')==changed['name'], 'Product update not visible'
        expect_response('DELETE',f'/api/admin/products/{pid}',{200},token=admin_token)
        return f'Disposable product {pid}: create/read/update/deactivate via admin token'
    test('AC03/05','Real admin CRUD lifecycle with authenticated admin',crud)
    def idempotency():
        pid=create_disposable(2,f'AC-IDEM-{runid}')
        key='ac-buy-'+uuid.uuid4().hex
        payload={'product_id':pid,'quantity':1}
        first=expect_response('POST','/api/purchases',{201},token=customer_token,data=payload,key=key)
        second=expect_response('POST','/api/purchases',{200,201},token=customer_token,data=payload,key=key)
        assert first.get('order_id')==second.get('order_id'),'Same-key replay created another order'
        expect_response('POST','/api/purchases',{409},token=customer_token,data={'product_id':pid,'quantity':2},key=key)
        prod=expect_response('GET',f'/api/admin/products/{pid}',{200},token=admin_token)
        assert prod.get('stock')==1,f'Expected stock 1 after only one sale; got {prod.get("stock")}'
        return f'One unique order, one stock decrement on product {pid}'
    test('AC06/07','Real customer buy, idempotency replay, fingerprint conflict',idempotency)
    def race():
        pid=create_disposable(5,f'AC-RACE-{runid}')
        def attempt(index):
            return api('POST','/api/purchases',token=customer_token,data={'product_id':pid,'quantity':1},key=f'ac-race-{runid}-{index}-{uuid.uuid4().hex}')
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            outcomes=list(executor.map(attempt,range(10)))
        codes=[code for code,_ in outcomes]
        count_success=codes.count(201)
        count_rejected=codes.count(409)
        assert count_success==5 and count_rejected==5,f'Expected 5x201 + 5x409, got {codes}'
        identifiers=[b.get('order_id') for s,b in outcomes if s==201 and isinstance(b,dict)]
        assert len(identifiers)==5 and len(set(identifiers))==5,'Expected five distinct successful orders'
        prod=expect_response('GET',f'/api/admin/products/{pid}',{200},token=admin_token)
        assert prod.get('stock')==0,f'Expected stock=0; got {prod.get("stock")}'
        return f'10 concurrent clients, 5 stock, 5 orders, 5 rejected, stock=0; product {pid}'
    test('AC07/08','Real concurrent buyers / no oversell',race)
    # Deactivation is the project-supported non-destructive cleanup. Test orders remain.
    for pid in created:
        try:
            api('DELETE',f'/api/admin/products/{pid}',token=admin_token)
        except Exception:pass

# Browser / Flutter acceptance is separate. No false PASS from API tests.
skip('AC01/04','Flutter UI/widget/mobile end-to-end acceptance','Python HTTP runner cannot validate Flutter rendering, cart state or Android payment return')
skip('AC06/07','Stripe end-to-end sandbox webhook, cancel, reconciliation','Excluded from this test to prevent actual Stripe session creation or duplicate payment')
skip('AC07/08','Production failure-recovery and sustained load','Requires separate resilience and sustained-load evidence')

counts={state:sum(1 for x in results if x['status']==state) for state in ['PASS','FAIL','ERROR','SKIP']}
report={'scope':'Node.js backend only; live local HTTP + SQL through API','base_url':BASE,'timestamp_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'disposable_writes_enabled':args.allow_disposable_writes,'counts':counts,'checks':results,'overall':'FAIL' if counts['FAIL']+counts['ERROR'] else 'INCOMPLETE' if counts['SKIP'] else 'PASS'}
Path(args.out).write_text(json.dumps(report,indent=2),encoding='utf-8')
for item in results:
    print(f"[{item['status']}] {item['criterion']} {item['name']}: {item['detail']}")
print('\nSUMMARY:',json.dumps(counts),'OVERALL:',report['overall'],'REPORT:',args.out)
sys.exit(1 if counts['FAIL']+counts['ERROR'] else 2 if counts['SKIP'] else 0)
