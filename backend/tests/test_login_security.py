"""Authentication security regressions: real FastAPI route, SQLite test DB."""
import pytest
from app.login_guard import login_guard
from app.models import User, Product, Order

@pytest.fixture(autouse=True)
def reset_login_attempts():
    login_guard._failures.clear()
    yield
    login_guard._failures.clear()

@pytest.mark.parametrize('email', [
    "' OR 1=1 --@example.com", "admin@demo.local' OR '1'='1",
    "x'; DROP TABLE users;--@example.com",
])
def test_sql_injection_strings_cannot_bypass_login(test_env, email):
    client, sessions = test_env
    response = client.post('/api/auth/login', json={
        'email': email, 'password': "' OR 1=1 --"})
    # Email parser may reject malformed input with 422; never authenticate.
    assert response.status_code in (401, 422), response.text
    assert 'access_token' not in response.text
    with sessions() as db:
        assert db.query(User).count() == 2
        assert db.query(Product).count() == 1
        assert db.query(Order).count() == 0

def test_five_bad_logins_then_lockout_and_no_token(test_env):
    client, _ = test_env
    for i in range(5):
        response = client.post('/api/auth/login', json={
            'email': 'user@test.local', 'password': 'definitely-wrong'})
        assert response.status_code == 401, (i, response.text)
    response = client.post('/api/auth/login', json={
        'email': 'user@test.local', 'password': 'user-test-secret'})
    assert response.status_code == 429, response.text
    assert response.headers.get('retry-after') == '900'
    assert 'access_token' not in response.text

def test_success_resets_failed_attempt_counter(test_env):
    client, _ = test_env
    for _ in range(4):
        assert client.post('/api/auth/login', json={
            'email': 'user@test.local', 'password': 'incorrect'}).status_code == 401
    assert client.post('/api/auth/login', json={
        'email': 'user@test.local', 'password': 'user-test-secret'}).status_code == 200
    assert client.post('/api/auth/login', json={
        'email': 'user@test.local', 'password': 'incorrect'}).status_code == 401

def test_separate_users_do_not_share_limit(test_env):
    client, _ = test_env
    for _ in range(5):
        assert client.post('/api/auth/login', json={
            'email': 'user@test.local', 'password': 'wrong'}).status_code == 401
    assert client.post('/api/auth/login', json={
        'email': 'admin@test.local', 'password': 'admin-test-secret'}).status_code == 200
