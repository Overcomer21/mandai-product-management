"""Fast local regression tests. SQL Server end-to-end tests are separate."""
from concurrent.futures import ThreadPoolExecutor
from sqlalchemy import select
from app.models import Order, OrderItem, Product
from .conftest import token


def test_duplicate_key_concurrent_retries_only_one_order(test_env):
    client, sessions = test_env
    buyer = token(client, 'user@test.local', 'user-test-secret')
    headers = {**buyer, 'Idempotency-Key': 'simultaneous-same-operation-001'}
    def call(_):
        return client.post('/api/purchases', json={'product_id':1,'quantity':1}, headers=headers)
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(call, range(4)))
    assert all(r.status_code == 201 for r in responses), [(r.status_code,r.text) for r in responses]
    assert len({r.json()['order_id'] for r in responses}) == 1
    with sessions() as db:
        assert db.get(Product,1).stock == 4
        assert len(db.scalars(select(Order)).all()) == 1
        assert len(db.scalars(select(OrderItem)).all()) == 1


def test_insufficient_stock_leaves_no_partial_order(test_env):
    client, sessions = test_env
    buyer = token(client, 'user@test.local', 'user-test-secret')
    result = client.post('/api/purchases',headers={**buyer,'Idempotency-Key':'insufficient-test-001'},json={'product_id':1,'quantity':6})
    assert result.status_code == 409, result.text
    with sessions() as db:
        assert db.get(Product,1).stock == 5
        assert db.scalars(select(Order)).all() == []
        assert db.scalars(select(OrderItem)).all() == []


def test_failed_crud_constraint_rolls_back(test_env):
    _, sessions = test_env
    from sqlalchemy.exc import IntegrityError
    import pytest
    with pytest.raises(IntegrityError):
        with sessions.begin() as db:
            db.get(Product,1).stock = -999
            db.flush()
    with sessions() as db:
        assert db.get(Product,1).stock == 5
