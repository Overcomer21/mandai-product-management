from concurrent.futures import ThreadPoolExecutor
from app.models import Product, Order, OrderItem, Payment
from .conftest import token

def test_cart_checkout_and_replay(test_env):
    client,sessions=test_env
    headers=token(client,'user@test.local','user-test-secret')
    headers['Idempotency-Key']='cart-test-000001'
    payload={'items':[{'product_id':1,'quantity':2}], 'delivery_address':'123 Example Road Singapore 123456', 'payment_method':'card_demo'}
    response=client.post('/api/checkout',headers=headers,json=payload)
    assert response.status_code==201,response.text
    data=response.json()
    assert data['payment_status']=='approved_demo'
    assert data['total_amount']=='44.90'
    replay=client.post('/api/checkout',headers=headers,json=payload)
    assert replay.status_code==201 and replay.json()['replayed']
    with sessions() as db:
        assert db.get(Product,1).stock==3
        assert db.query(Order).count()==1
        assert db.query(OrderItem).count()==1
        assert db.query(Payment).count()==1
        assert db.query(Payment).first().card_last4=='4242'

def test_decline_does_not_create_order(test_env):
    client,sessions=test_env
    headers=token(client,'user@test.local','user-test-secret')
    headers['Idempotency-Key']='decline-test-001'
    payload={'items':[{'product_id':1,'quantity':1}], 'delivery_address':'123 Example Road Singapore 123456', 'payment_method':'card_demo','simulate_decline':True}
    r=client.post('/api/checkout',headers=headers,json=payload)
    assert r.status_code==402
    with sessions() as db:
        assert db.get(Product,1).stock==5
        assert db.query(Order).count()==0
        assert db.query(Payment).count()==0

def test_multiitem_invalid_order_rollback(test_env):
    client,sessions=test_env
    headers=token(client,'user@test.local','user-test-secret')
    headers['Idempotency-Key']='rollback-test-01'
    payload={'items':[{'product_id':1,'quantity':1},{'product_id':9999,'quantity':1}], 'delivery_address':'123 Example Road Singapore 123456', 'payment_method':'paynow_demo'}
    r=client.post('/api/checkout',headers=headers,json=payload)
    assert r.status_code==404
    with sessions() as db:
        assert db.get(Product,1).stock==5
        assert db.query(Order).count()==0

def test_checkout_requires_user(test_env):
    client,_=test_env
    headers=token(client,'admin@test.local','admin-test-secret')
    headers['Idempotency-Key']='admin-attempt-001'
    data={'items':[{'product_id':1,'quantity':1}], 'delivery_address':'123 Example Road Singapore 123456', 'payment_method':'card_demo'}
    assert client.post('/api/checkout',headers=headers,json=data).status_code==403
    assert client.post('/api/checkout',json=data).status_code==401

def test_concurrent_cart_orders_not_oversell(test_env):
    client,sessions=test_env
    headers=token(client,'user@test.local','user-test-secret')
    data={'items':[{'product_id':1,'quantity':1}], 'delivery_address':'123 Example Road Singapore 123456', 'payment_method':'card_demo'}
    def request(i):
        return client.post('/api/checkout',headers={**headers,'Idempotency-Key':f'parallel-cart-{i:04d}'},json=data)
    with ThreadPoolExecutor(max_workers=10) as pool:
        results=list(pool.map(request,range(10)))
    assert sum(r.status_code==201 for r in results)==5,[(r.status_code,r.text) for r in results]
    assert sum(r.status_code==409 for r in results)==5
    with sessions() as db:
        assert db.get(Product,1).stock==0
        assert db.query(Order).count()==5
        assert db.query(Payment).count()==5
