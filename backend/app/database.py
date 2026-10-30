import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from sqlalchemy.orm import sessionmaker, DeclarativeBase

load_dotenv(Path(__file__).resolve().parent.parent / '.env')


class Base(DeclarativeBase):
    pass

def database_url():
    # Set a SQL Server ODBC connection string through environment variables.
    # SQLite is only a lightweight local test alternative, NOT the recommended server mode.
    if os.getenv('DATABASE_URL'):
        return os.environ['DATABASE_URL']
    return URL.create(
        'mssql+pyodbc',
        username=os.getenv('DB_USER', 'mandai_app'),
        password=os.getenv('DB_PASSWORD', ''),
        host=os.getenv('DB_HOST', 'localhost'),
        port=int(os.getenv('DB_PORT', '1433')),
        database=os.getenv('DB_NAME', 'MandaiAssessment'),
        query={'driver':'ODBC Driver 17 for SQL Server',
               'Encrypt':os.getenv('DB_ENCRYPT','yes'),
               'TrustServerCertificate':os.getenv('DB_TRUST_CERT','no')},
    )

def make_engine():
    url=database_url()
    if str(url).startswith('sqlite'):
        return create_engine(url, connect_args={'check_same_thread':False, 'timeout':20})
    # Explicit bounded pool settings for SQL Server, configurable for benchmark environments.
    # Pool limits apply per worker process; do not increase without measuring SQL capacity.
    pool_size = int(os.getenv('DB_POOL_SIZE', '10'))
    max_overflow = int(os.getenv('DB_MAX_OVERFLOW', '10'))
    pool_timeout = int(os.getenv('DB_POOL_TIMEOUT', '10'))
    if pool_size < 1 or max_overflow < 0 or pool_timeout < 1:
        raise ValueError('Invalid SQL Server connection pool configuration')
    return create_engine(
        url,
        pool_pre_ping=True,
        pool_size=pool_size,
        max_overflow=max_overflow,
        pool_timeout=pool_timeout,
    )

engine=make_engine()
SessionLocal=sessionmaker(bind=engine, expire_on_commit=False)

def get_db():
    with SessionLocal() as session:
        yield session
