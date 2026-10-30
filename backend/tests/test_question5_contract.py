"""Question 5 HTTP contracts; isolated SQLite fixture, no MandaiDB writes."""
from concurrent.futures import ThreadPoolExecutor
from sqlalchemy import select
from app.models import Product, Order, OrderItem
from .conftest import token


def test_storefront_catalog_and_details(test_env):
    client, _ = test_env
    response = client.get('/api/products')
    assert response.status_code == 200
    entries = response.json()
    assert len(entries) == 1
    entry = entries[0]
    assert set(('id','name','category','price','stock','is_active')).issubset(entry)
    assert client.get(f"/api/products/{entry['id']}").status_code == 200


def test_admin_inventory_crud_and_role_enforcement(test_env):
    client, sessions = test_env
    admin = token(client, 'admin@test.local','admin-test-secret')
    user = token(client, 'user@test.local','user-test-secret')
    payload = dict(name='Q5 TEST', description='Isolated', category='Tests', price='8.50',stock=3,is_active=True)
    assert client.post('/api/admin/products',json=payload).status_code == 401
    assert client.post('/api/admin/products',headers=user,json=payload).status_code == 403
    created = client.post('/api/admin/products', headers=admin,json=payload)
    assert created.status_code == 201, created.text
    pid = created.json()['id']
    assert client.get(f'/api/admin/products/{pid}',headers=user).status_code == 403
    assert client.get(f'/api/admin/products/{pid}',headers=admin).status_code == 200
    payload['stock'] = 7
    assert client.put(f'/api/admin/products/{pid}',headers=admin,json=payload).status_code == 200
    assert client.get(f'/api/products/{pid}').json()['stock'] == 7
    assert client.delete(f'/api/admin/products/{pid}',headers=user).status_code == 403
    assert client.delete(f'/api/admin/products/{pid}',headers=admin).status_code == 200
    assert client.get(f'/api/products/{pid}').status_code == 404
    with sessions() as db:
        assert db.get(Product,pid) is None


def test_customer_buy_atomic_and_replay(test_env):
    client,sessions=test_env
    user=token(client,'user@test.local','user-test-secret')
    admin=token(client,'admin@test.local','admin-test-secret')
    h={**user,'Idempotency-Key':'q5-customer-buy-001'}
    body={'product_id':1,'quantity':2}
    assert client.post('/api/purchases',json=body,headers={**admin,'Idempotency-Key':'q5-admin-denied-001'}).status_code==403
    first=client.post('/api/purchases',json=body,headers=h)
    assert first.status_code==201,first.text
    replay=client.post('/api/purchases',json=body,headers=h)
    assert replay.status_code==201 and replay.json()['replayed'] is True
    assert first.json()['order_id']==replay.json()['order_id']
    assert client.post('/api/purchases',json={'product_id':1,'quantity':1},headers=h).status_code==409
    with sessions() as db:
        assert db.get(Product,1).stock == 3
        assert len(db.scalars(select(Order)).all())==1
        assert len(db.scalars(select(OrderItem)).all())==1


def test_buy_concurrency_no_overselling_sqlite_regression(test_env):
    # SQLite regression only; does NOT prove SQL Server isolation or locking.
    client,sessions=test_env
    user=token(client,'user@test.local','user-test-secret')
    def purchase(i):
        return client.post('/api/purchases',headers={**user,'Idempotency-Key':f'q5-concurrent-{i:04d}'},json={'product_id':1,'quantity':1})
    with ThreadPoolExecutor(max_workers=10) as pool:
        responses=list(pool.map(purchase,range(10)))
    codes=[r.status_code for r in responses]
    assert codes.count(201)==5 and codes.count(409)==5,[(r.status_code,r.text) for r in responses]
    with sessions() as db:
        assert db.get(Product,1).stock==0
        assert len(db.scalars(select(Order)).all())==5
