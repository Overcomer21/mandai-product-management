from concurrent.futures import ThreadPoolExecutor
from sqlalchemy import select
from app.models import Product, Order, OrderItem
from .conftest import token

def test_auth_and_crud(test_env):
    client,_=test_env
    admin=token(client,'admin@test.local','admin-test-secret')
    buyer=token(client,'user@test.local','user-test-secret')
    assert client.get('/api/admin/products').status_code==401
    assert client.get('/api/admin/products',headers=buyer).status_code==403
    payload={'name':'Tote','description':'Test','category':'Gifts','price':'10.50','stock':3,'is_active':True}
    created=client.post('/api/admin/products',headers=admin,json=payload)
    assert created.status_code==201,created.text
    pid=created.json()['id']
    assert client.get('/api/admin/products/'+str(pid),headers=admin).status_code==200
    payload['stock']=4
    assert client.put('/api/admin/products/'+str(pid),headers=admin,json=payload).status_code==200
    assert client.delete('/api/admin/products/'+str(pid),headers=admin).status_code==200
    assert client.get('/api/products/'+str(pid)).status_code==404
    payload['stock']=-1
    assert client.post('/api/admin/products',headers=admin,json=payload).status_code==422

def test_buy_idempotency_and_rollback(test_env):
    client,sessions=test_env
    buyer=token(client,'user@test.local','user-test-secret')
    h={**buyer,'Idempotency-Key':'unique-order-001'}
    body={'product_id':1,'quantity':2}
    first=client.post('/api/purchases',headers=h,json=body)
    assert first.status_code==201,first.text
    again=client.post('/api/purchases',headers=h,json=body)
    assert again.status_code==201 and again.json()['replayed'] is True
    changed=client.post('/api/purchases',headers=h,json={'product_id':1,'quantity':1})
    assert changed.status_code==409
    fail=client.post('/api/purchases',headers={**buyer,'Idempotency-Key':'different-order-002'},json={'product_id':1,'quantity':9})
    assert fail.status_code==409,fail.text
    with sessions() as db:
        assert db.get(Product,1).stock==3
        assert len(db.scalars(select(Order)).all())==1
        assert len(db.scalars(select(OrderItem)).all())==1

def test_concurrent_buyers_no_oversell(test_env):
    client,sessions=test_env
    buyer=token(client,'user@test.local','user-test-secret')
    def buy(i):
        return client.post('/api/purchases',headers={**buyer,'Idempotency-Key':f'concurrent-key-{i:04d}'},json={'product_id':1,'quantity':1}).status_code
    with ThreadPoolExecutor(max_workers=10) as ex:
        results=list(ex.map(buy,range(10)))
    assert results.count(201)==5,results
    assert results.count(409)==5,results
    with sessions() as db:
        assert db.get(Product,1).stock==0
        assert len(db.scalars(select(Order)).all())==5

def test_invalid_token_and_purchase_input(test_env):
    client,sessions=test_env
    assert client.get('/api/admin/products',headers={'Authorization':'Bearer invalid'}).status_code==401
    buyer=token(client,'user@test.local','user-test-secret')
    headers={**buyer,'Idempotency-Key':'invalid-input-001'}
    assert client.post('/api/purchases',headers=headers,json={'product_id':1,'quantity':0}).status_code==422
    assert client.post('/api/purchases',headers=headers,json={'product_id':1,'quantity':-1}).status_code==422
    with sessions() as db:
        assert db.get(Product,1).stock==5
        assert len(db.scalars(select(Order)).all())==0

def test_purchase_uses_server_side_price(test_env):
    client,sessions=test_env
    admin=token(client,'admin@test.local','admin-test-secret')
    buyer=token(client,'user@test.local','user-test-secret')
    edit={'name':'Panda Plush','description':'demo','category':'Plush','price':'25.75','stock':5,'is_active':True}
    updated=client.put('/api/admin/products/1',headers=admin,json=edit)
    assert updated.status_code==200,updated.text
    response=client.post('/api/purchases',headers={**buyer,'Idempotency-Key':'server-price-001'},json={'product_id':1,'quantity':2})
    assert response.status_code==201,response.text
    assert str(response.json()['total_amount']) in ('51.5','51.50')
    with sessions() as db:
        order=db.scalars(select(Order)).one()
        assert str(order.total_amount)=='51.50'
        assert db.get(Product,1).stock==3
