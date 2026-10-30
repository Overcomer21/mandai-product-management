import os
import tempfile
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# In-memory/test-file sqlite is for fast API tests only; SQL Server integration tests are separate.
if os.getenv('MANDAI_SQLSERVER_TEST') != '1':
    os.environ.setdefault('DATABASE_URL', 'sqlite:///./mandai_test_bootstrap.db')
os.environ.setdefault('JWT_SECRET','TEST_ONLY_SUPER_LONG_SECRET_WITH_32_CHARS_12345')
from app.database import Base,get_db
from app.main import app
from app.models import User,Product
from app.security import hash_password

@pytest.fixture
def test_env(tmp_path):
    engine=create_engine('sqlite:///'+str(tmp_path/'test.db'),connect_args={'check_same_thread':False,'timeout':30})
    Base.metadata.create_all(engine)
    sessions=sessionmaker(bind=engine,expire_on_commit=False)
    with sessions.begin() as db:
        db.add_all([User(email='admin@test.local',password_hash=hash_password('admin-test-secret'),role='admin'),User(email='user@test.local',password_hash=hash_password('user-test-secret'),role='user'),Product(name='Panda Plush',description='demo',category='Plush',price=20,stock=5,is_active=True)])
    app.dependency_overrides[get_db]=lambda: sessions()
    with TestClient(app) as client:
        yield client,sessions
    app.dependency_overrides.clear();engine.dispose()

def session_override(sessions):
    with sessions() as db:yield db

def token(client,email,password):
    res=client.post('/api/auth/login',json={'email':email,'password':password})
    assert res.status_code==200,res.text
    return {'Authorization':'Bearer '+res.json()['access_token']}
