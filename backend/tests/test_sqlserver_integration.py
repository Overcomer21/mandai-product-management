"""Real SQL Server + running FastAPI verification; never run against production.

Run with:
  $env:MANDAI_SQLSERVER_TEST='1'
  $env:API_TEST_BASE='http://127.0.0.1:8000'
  $env:DEMO_USER_PASSWORD='...'
  $env:DEMO_ADMIN_PASSWORD='...'
  python -m pytest -q tests/test_sqlserver_integration.py -s

Test creates uniquely named products, and deactivates them on teardown.
"""
import os
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
import httpx
import pytest
from sqlalchemy import select
from app.database import SessionLocal, engine
from app.models import Product, Order, OrderItem

pytestmark = pytest.mark.skipif(os.getenv('MANDAI_SQLSERVER_TEST') != '1', reason='Requires opted-in SQL Server integration run')

@pytest.fixture(scope='module')
def server():
    if engine.dialect.name != 'mssql':
        pytest.skip('DATABASE_URL/DB_* must point to SQL Server, not SQLite')
    base = os.getenv('API_TEST_BASE', 'http://127.0.0.1:8000')
    with httpx.Client(base_url=base, timeout=30) as api:
        health = api.get('/health')
        health.raise_for_status()
    yield base

@pytest.fixture(scope='module')
def auth(server):
    result = {}
    for role in ('user','admin'):
        password = os.environ[f'DEMO_{role.upper()}_PASSWORD']
        email = f'{role}@demo.local'
        with httpx.Client(base_url=server, timeout=30) as api:
            r = api.post('/api/auth/login',json={'email':email,'password':password})
        assert r.status_code == 200, r.text
        result[role] = {'Authorization':'Bearer '+r.json()['access_token']}
    return result

@pytest.fixture
def product():
    with SessionLocal.begin() as db:
        p = Product(name='TEST_ONLY_'+uuid4().hex,description='Concurrency test',category='Tests',price=12.50,stock=5,is_active=True)
        db.add(p)
        db.flush()
        pid = p.id
    yield pid
    with SessionLocal.begin() as db:
        p=db.get(Product,pid)
        if p: p.is_active=False


def _purchase(base,headers,product_id,quantity,key):
    with httpx.Client(base_url=base,timeout=60) as api:
        return api.post('/api/purchases',json={'product_id':product_id,'quantity':quantity},headers={**headers,'Idempotency-Key':key})


def test_concurrent_buyers_no_overselling(server,auth,product):
    prefix='concurrent-'+uuid4().hex+'-'
    with ThreadPoolExecutor(max_workers=10) as pool:
        responses=list(pool.map(lambda n:_purchase(server,auth['user'],product,1,prefix+str(n)),range(10)))
    statuses=[r.status_code for r in responses]
    assert statuses.count(201)==5 and statuses.count(409)==5, [(r.status_code,r.text) for r in responses]
    with SessionLocal() as db:
        assert db.get(Product,product).stock == 0
        orders=db.scalars(select(Order).join(OrderItem).where(OrderItem.product_id==product)).all()
        assert len(orders)==5
        assert len({o.id for o in orders})==5
        assert sum(db.scalars(select(OrderItem.quantity).where(OrderItem.product_id==product)).all())==5


def test_concurrent_same_key_single_purchase(server,auth,product):
    key='retry-'+uuid4().hex
    with ThreadPoolExecutor(max_workers=5) as pool:
        responses=list(pool.map(lambda _: _purchase(server,auth['user'],product,2,key),range(5)))
    assert all(r.status_code==201 for r in responses), [(r.status_code,r.text) for r in responses]
    assert len({r.json()['order_id'] for r in responses})==1
    with SessionLocal() as db:
        assert db.get(Product,product).stock == 3
        assert len(db.scalars(select(Order).where(Order.idempotency_key==key)).all())==1


def test_insufficient_stock_atomic_rollback(server,auth,product):
    r=_purchase(server,auth['user'],product,6,'reject-'+uuid4().hex)
    assert r.status_code==409, (r.status_code,r.text)
    with SessionLocal() as db:
        assert db.get(Product,product).stock==5
        assert len(db.scalars(select(Order).join(OrderItem).where(OrderItem.product_id==product)).all())==0


def test_admin_crud_and_role_protection(server,auth):
    sample={'name':'TEST_ONLY_'+uuid4().hex,'description':'QA','category':'Tests','price':'19.50','stock':3,'is_active':True}
    with httpx.Client(base_url=server,timeout=30) as api:
        assert api.post('/api/admin/products',json=sample,headers=auth['user']).status_code==403
        assert api.get('/api/admin/products').status_code==401
        created=api.post('/api/admin/products',json=sample,headers=auth['admin'])
        assert created.status_code==201,created.text
        pid=created.json()['id']
        try:
            assert api.get(f'/api/admin/products/{pid}',headers=auth['admin']).status_code==200
            sample['stock']=7
            updated=api.put(f'/api/admin/products/{pid}',json=sample,headers=auth['admin'])
            assert updated.status_code==200 and updated.json()['stock']==7,updated.text
            deleted=api.delete(f'/api/admin/products/{pid}',headers=auth['admin'])
            assert deleted.status_code==200,deleted.text
            assert api.get(f'/api/products/{pid}').status_code==404
        finally:
            with SessionLocal.begin() as db:
                p=db.get(Product,pid)
                if p:p.is_active=False
