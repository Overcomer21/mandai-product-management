"""Additional live SQL Server checkout tests; complements existing test_sqlserver_integration.py.

WARNING: Run only against a disposable SQL Server TEST database. These tests
create test orders and payments and do not delete audit records on teardown.
Requires MANDAI_SQLSERVER_TEST=1 and an already running API.
"""
import os
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import httpx
import pytest
from sqlalchemy import select
from app.database import SessionLocal, engine
from app.models import Product, Order, OrderItem, Payment
from .test_sqlserver_integration import server, auth, product  # reuse existing test fixtures

pytestmark = pytest.mark.skipif(
    os.getenv('MANDAI_SQLSERVER_TEST') != '1',
    reason='Opt-in test: requires real SQL Server and running FastAPI',
)


def _checkout(base, headers, pid, quantity, key, *, address='123 Test Avenue Singapore 123456'):
    body = {
        'items': [{'product_id': pid, 'quantity': quantity}],
        'delivery_address': address,
        'payment_method': 'card_demo',
    }
    with httpx.Client(base_url=base, timeout=60) as client:
        return client.post('/api/checkout', json=body,
                           headers={**headers, 'Idempotency-Key': key})


def _orders_for_product(db, pid):
    return db.scalars(select(Order).join(OrderItem).where(OrderItem.product_id == pid)).all()


def test_checkout_concurrent_unique_keys_no_oversell(server, auth, product):
    prefix = 'checkout-parallel-' + uuid4().hex + '-'
    with ThreadPoolExecutor(max_workers=10) as executor:
        responses = list(executor.map(
            lambda i: _checkout(server, auth['user'], product, 1, prefix + str(i)),
            range(10),
        ))
    codes = [response.status_code for response in responses]
    assert codes.count(201) == 5 and codes.count(409) == 5, [
        (r.status_code, r.text) for r in responses
    ]
    with SessionLocal() as db:
        assert db.get(Product, product).stock == 0
        orders = _orders_for_product(db, product)
        assert len(orders) == 5
        assert len({order.id for order in orders}) == 5
        assert sum(item.quantity for order in orders for item in order.items) == 5
        for order in orders:
            payments = db.scalars(select(Payment).where(Payment.order_id == order.id)).all()
            assert len(payments) == 1
            assert payments[0].status == 'approved_demo'


def test_checkout_same_key_replay_no_duplicate_order_or_payment(server, auth, product):
    key = 'checkout-replay-' + uuid4().hex
    with ThreadPoolExecutor(max_workers=4) as executor:
        responses = list(executor.map(
            lambda _: _checkout(server, auth['user'], product, 2, key), range(4),
        ))
    assert all(r.status_code == 201 for r in responses), [
        (r.status_code, r.text) for r in responses
    ]
    ids = {r.json()['order_id'] for r in responses}
    assert len(ids) == 1
    assert sum(r.json()['replayed'] is False for r in responses) == 1
    with SessionLocal() as db:
        assert db.get(Product, product).stock == 3
        orders = db.scalars(select(Order).where(Order.idempotency_key == key)).all()
        assert len(orders) == 1
        assert len(orders[0].items) == 1
        assert orders[0].items[0].quantity == 2
        assert len(db.scalars(select(Payment).where(Payment.order_id == orders[0].id)).all()) == 1


def test_checkout_same_key_different_payload_is_rejected(server, auth, product):
    key = 'checkout-conflict-' + uuid4().hex
    accepted = _checkout(server, auth['user'], product, 1, key)
    assert accepted.status_code == 201, accepted.text
    rejected = _checkout(server, auth['user'], product, 2, key)
    assert rejected.status_code == 409, rejected.text
    with SessionLocal() as db:
        assert db.get(Product, product).stock == 4
        orders = db.scalars(select(Order).where(Order.idempotency_key == key)).all()
        assert len(orders) == 1
        assert len(db.scalars(select(Payment).where(Payment.order_id == orders[0].id)).all()) == 1


def test_checkout_insufficient_stock_rolls_back_order_and_payment(server, auth, product):
    key = 'checkout-insufficient-' + uuid4().hex
    response = _checkout(server, auth['user'], product, 6, key)
    assert response.status_code == 409, response.text
    with SessionLocal() as db:
        assert db.get(Product, product).stock == 5
        assert db.scalars(select(Order).where(Order.idempotency_key == key)).all() == []
        assert _orders_for_product(db, product) == []


def test_checkout_rejects_duplicate_product_ids(server, auth, product):
    key = 'checkout-duplicate-product-' + uuid4().hex
    data = {
        'items': [{'product_id': product, 'quantity': 1},
                  {'product_id': product, 'quantity': 1}],
        'delivery_address': '123 Test Avenue Singapore 123456',
        'payment_method': 'card_demo',
    }
    with httpx.Client(base_url=server, timeout=60) as client:
        response = client.post('/api/checkout', json=data,
                               headers={**auth['user'], 'Idempotency-Key': key})
    assert response.status_code == 422, response.text
    with SessionLocal() as db:
        assert db.get(Product, product).stock == 5
        assert db.scalars(select(Order).where(Order.idempotency_key == key)).all() == []
