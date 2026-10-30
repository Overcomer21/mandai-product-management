"""Security regression for /api/purchases. Uses existing isolated SQLite test_env fixture."""
from sqlalchemy import select
from app.models import Product, Order, OrderItem
from .conftest import token


def test_admin_purchase_denied_without_mutation(test_env):
    client, sessions = test_env
    headers = token(client, 'admin@test.local', 'admin-test-secret')
    response = client.post('/api/purchases', headers={**headers, 'Idempotency-Key': 'admin-forbidden-001'}, json={'product_id': 1, 'quantity': 1})
    assert response.status_code == 403, response.text
    assert response.json()['detail'] == 'Only customers can purchase'
    with sessions() as db:
        assert db.get(Product, 1).stock == 5
        assert db.scalars(select(Order)).all() == []
        assert db.scalars(select(OrderItem)).all() == []


def test_guest_purchase_denied_without_mutation(test_env):
    client, sessions = test_env
    response = client.post('/api/purchases', headers={'Idempotency-Key': 'guest-forbidden-001'}, json={'product_id': 1, 'quantity': 1})
    assert response.status_code == 401, response.text
    with sessions() as db:
        assert db.get(Product, 1).stock == 5
        assert db.scalars(select(Order)).all() == []


def test_customer_purchase_still_succeeds(test_env):
    client, sessions = test_env
    headers = token(client, 'user@test.local', 'user-test-secret')
    response = client.post('/api/purchases', headers={**headers, 'Idempotency-Key': 'customer-allowed-001'}, json={'product_id': 1, 'quantity': 1})
    assert response.status_code == 201, response.text
    assert response.json()['status'] == 'completed'
    with sessions() as db:
        assert db.get(Product, 1).stock == 4
        assert len(db.scalars(select(Order)).all()) == 1
        assert len(db.scalars(select(OrderItem)).all()) == 1
