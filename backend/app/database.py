
import logging
import os
import time
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine, event
from sqlalchemy.engine import URL
from sqlalchemy.orm import sessionmaker, DeclarativeBase


# ---------------------------------------------------------
# Environment Configuration
# ---------------------------------------------------------

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

logger = logging.getLogger("mandai.performance")

SLOW_QUERY_MS = float(os.getenv("SLOW_QUERY_MS", "100"))

if not 0 < SLOW_QUERY_MS < float("inf"):
    raise ValueError("SLOW_QUERY_MS must be a finite positive number")


class Base(DeclarativeBase):
    pass


# ---------------------------------------------------------
# Database Configuration
# ---------------------------------------------------------

def database_url():
    # Preserve explicitly configured connection strings.
    if os.getenv("DATABASE_URL"):
        return os.environ["DATABASE_URL"]

    return URL.create(
        "mssql+pyodbc",
        username=os.getenv("DB_USER", "mandai_app"),
        password=os.getenv("DB_PASSWORD", ""),
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "1433")),
        database=os.getenv("DB_NAME", "MandaiAssessment"),
        query={
            "driver": "ODBC Driver 17 for SQL Server",
            "Encrypt": os.getenv("DB_ENCRYPT", "yes"),
            "TrustServerCertificate": os.getenv(
                "DB_TRUST_CERT", "no"
            ),
        },
    )


# ---------------------------------------------------------
# SQLAlchemy Engine
# ---------------------------------------------------------

def make_engine():
    url = database_url()

    # Preserve existing SQLite test configuration.
    if str(url).startswith("sqlite"):
        return create_engine(
            url,
            connect_args={
                "check_same_thread": False,
                "timeout": 20,
            },
        )

    # Preserve existing bounded SQL Server pool configuration.
    pool_size = int(os.getenv("DB_POOL_SIZE", "10"))
    max_overflow = int(os.getenv("DB_MAX_OVERFLOW", "10"))
    pool_timeout = int(os.getenv("DB_POOL_TIMEOUT", "10"))

    if pool_size < 1 or max_overflow < 0 or pool_timeout < 1:
        raise ValueError(
            "Invalid SQL Server connection pool configuration"
        )

    return create_engine(
        url,
        pool_pre_ping=True,
        pool_size=pool_size,
        max_overflow=max_overflow,
        pool_timeout=pool_timeout,
    )


engine = make_engine()


# ---------------------------------------------------------
# Database Connection Pool Monitoring
# ---------------------------------------------------------

def get_pool_metrics():
    """
    Return read-only SQLAlchemy connection pool metrics.

    Metrics are local to this backend process.
    """

    pool = engine.pool

    def read_metric(name):
        metric = getattr(pool, name, None)

        if callable(metric):
            return metric()

        return None

    pool_size = read_metric("size")
    checked_out = read_metric("checkedout")
    checked_in = read_metric("checkedin")
    raw_overflow = read_metric("overflow")

    # SQLAlchemy QueuePool reports negative overflow
    # when the pool has fewer connections than pool_size.
    # This is normal and must not be interpreted as an error.
    overflow = (
        max(0, raw_overflow)
        if raw_overflow is not None
        else None
    )

    max_overflow = getattr(pool, "_max_overflow", None)

    max_capacity = (
        pool_size + max_overflow
        if pool_size is not None and max_overflow is not None
        else None
    )

    utilization = None

    if (
        checked_out is not None
        and max_capacity is not None
        and max_capacity > 0
    ):
        utilization = round(
            checked_out / max_capacity * 100,
            2,
        )

    return {
        "pool_size": pool_size,
        "checked_out": checked_out,
        "checked_in": checked_in,
        "overflow": overflow,
        "max_capacity": max_capacity,
        "utilization_percent": utilization,
        "status": pool.status(),
    }


@event.listens_for(engine, "checkout")
def monitor_pool_checkout(
    dbapi_connection,
    connection_record,
    connection_proxy,
):
    """
    Lightweight checkout monitoring.

    Avoid collecting detailed pool metrics for every checkout.
    """

    try:
        pool = engine.pool

        checked_out = pool.checkedout()
        max_capacity = (
            pool.size() + pool._max_overflow
            if hasattr(pool, "_max_overflow")
            else None
        )

        if (
            max_capacity is not None
            and checked_out >= max_capacity
        ):
            logger.warning(
                "DB_POOL_CAPACITY_REACHED "
                "checked_out=%s max_capacity=%s",
                checked_out,
                max_capacity,
            )

    except Exception:
        # Monitoring must never interrupt database checkout.
        logger.debug(
            "Database pool monitoring failed",
            exc_info=True,
        )


# ---------------------------------------------------------
# SQL Query Performance Monitoring
# ---------------------------------------------------------

def get_sql_operation(statement):
    """
    Return the first SQL keyword only.
    Never log SQL statements or bound parameters.
    """

    parts = statement.lstrip().split(None, 1)

    return parts[0].upper() if parts else "UNKNOWN"


def log_query_duration(
    context,
    statement,
    failed=False,
):
    """
    Record SQL execution duration without exposing
    SQL statements, parameter values or credentials.
    """

    try:
        started = getattr(
            context,
            "_mandai_query_started",
            None,
        )

        if started is None:
            return

        elapsed_ms = (
            time.perf_counter() - started
        ) * 1000

        context._mandai_query_started = None

        if elapsed_ms >= SLOW_QUERY_MS:
            logger.warning(
                "SLOW_DB_QUERY operation=%s "
                "duration_ms=%.2f failed=%s",
                get_sql_operation(statement),
                elapsed_ms,
                failed,
            )

    except Exception:
        # Diagnostic failures must not affect application logic.
        logger.debug(
            "Database query monitoring failed",
            exc_info=True,
        )


@event.listens_for(engine, "before_cursor_execute")
def monitor_query_start(
    conn,
    cursor,
    statement,
    parameters,
    context,
    executemany,
):
    try:
        context._mandai_query_started = time.perf_counter()
    except Exception:
        logger.debug(
            "Unable to start query monitoring",
            exc_info=True,
        )


@event.listens_for(engine, "after_cursor_execute")
def monitor_query_end(
    conn,
    cursor,
    statement,
    parameters,
    context,
    executemany,
):
    log_query_duration(
        context,
        statement,
        failed=False,
    )


@event.listens_for(engine, "handle_error")
def monitor_query_error(exception_context):
    try:
        context = exception_context.execution_context

        if context is None:
            return

        statement = exception_context.statement or ""

        log_query_duration(
            context,
            statement,
            failed=True,
        )

    except Exception:
        logger.debug(
            "Database error monitoring failed",
            exc_info=True,
        )


# ---------------------------------------------------------
# Database Session Management
# ---------------------------------------------------------

# Preserve existing session configuration.
SessionLocal = sessionmaker(
    bind=engine,
    expire_on_commit=False,
)


def get_db():
    # Preserve existing context-managed session lifecycle.
    with SessionLocal() as session:
        yield session
