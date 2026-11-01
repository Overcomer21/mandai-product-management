"""Explicitly-enabled, admin-only SQL Server integration diagnostics.

Creates disposable test entities; never operates on customer inventory.
Results are computed from real checkout requests and database assertions.
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from decimal import Decimal
import os
import threading
import time
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, func, select, text
from sqlalchemy.orm import Session, sessionmaker

from .database import get_db
from .models import User, Product, Order, OrderItem, Payment
from .schemas import CheckoutInput
from .security import admin_only

router = APIRouter()
_running = threading.Lock()


def luhn_valid(value: str) -> bool:
    if not value.isascii() or not value.isdigit() or not 12 <= len(value) <= 19:
        return False
    digits = [int(x) for x in value]
    checksum = 0
    for position, digit in enumerate(reversed(digits)):
        if position % 2:
            digit *= 2
            if digit > 9:
                digit -= 9
        checksum += digit
    return checksum % 10 == 0


def run_suite(db: Session) -> dict:
    # SQL Server only: integration tests require production-equivalent database semantics.
    engine = db.get_bind()
    if engine.dialect.name != 'mssql':
        raise HTTPException(409, 'Concurrency integration tests require SQL Server (mssql).')
    SessionFactory = sessionmaker(bind=engine, expire_on_commit=False)
    run_id = uuid.uuid4().hex[:12]
    user_email = f'concurrency-test-{run_id}@example.invalid'
    test_user_id = None
    product_ids = []
    cases = []
    start = datetime.now(timezone.utc)
    from .api.routes.orders import checkout

    def stamp():
        return datetime.now(timezone.utc).isoformat(timespec='milliseconds')

    def register(name, txid, expected, action):
        begun = time.perf_counter()
        at = stamp()
        try:
            actual, details, ok, order_id = action()
        except Exception as exc:
            actual, details, ok, order_id = 'ERROR', f'{type(exc).__name__}: {exc}', False, None
        cases.append({'test_case': name, 'transaction_id': txid,
                      'testing_status': 'PASS' if ok else 'FAIL',
                      'transaction_status': actual, 'expected_result': expected,
                      'details': details, 'order_id': order_id,
                      'executed_at': at, 'duration_ms': round((time.perf_counter()-begun)*1000, 2)})

    def create_product(stock):
        with SessionFactory() as s:
            product = Product(name=f'[CONCURRENCY TEST {run_id}]', description='Disposable test item',
                              category='Tests', price=Decimal('7.00'), stock=stock, is_active=True)
            s.add(product)
            s.commit()
            product_ids.append(product.id)
            return product.id

    def stock_of(pid):
        with SessionFactory() as s:
            return s.scalar(select(Product.stock).where(Product.id == pid))

    def orders_for(key):
        with SessionFactory() as s:
            return s.scalars(select(Order).where(Order.user_id == test_user_id,
                                                  Order.idempotency_key == key)).all()

    def submit(pid, key, qty=1):
        with SessionFactory() as s:
            user = s.get(User, test_user_id)
            body = CheckoutInput(items=[{'product_id': pid, 'quantity': qty}],
                                 delivery_address='Automated integration test only',
                                 payment_method='card_demo', simulate_decline=False)
            try:
                return ('Completed', checkout(body=body, idempotency_key=key, db=s, user=user))
            except HTTPException as exc:
                return (f'Rejected — HTTP {exc.status_code}', str(exc.detail))
            except Exception as exc:
                s.rollback()
                return ('ERROR', f'{type(exc).__name__}: {exc}')

    try:
        with SessionFactory() as s:
            test_user = User(email=user_email, password_hash='DISABLED-TEST-ACCOUNT', role='user')
            s.add(test_user)
            s.commit()
            test_user_id = test_user.id

        p1 = create_product(2)
        key1 = f'test-{run_id}-valid'
        def valid():
            status, data = submit(p1, key1)
            rows = orders_for(key1)
            ok = status == 'Completed' and len(rows) == 1 and stock_of(p1) == 1 and data.get('replayed') is False
            return status, f'Order count={len(rows)}, remaining stock={stock_of(p1)}, replayed={data.get("replayed") if isinstance(data, dict) else "n/a"}', ok, rows[0].id if rows else None
        register('Valid Checkout and Atomic Inventory Decrement', key1,
                 'One order committed, stock reduced exactly once', valid)

        def replay():
            status, data = submit(p1, key1)
            rows = orders_for(key1)
            ok = status == 'Completed' and isinstance(data, dict) and data.get('replayed') is True and len(rows) == 1 and stock_of(p1) == 1
            return 'Completed — Idempotent Replay' if ok else status, f'Same key replayed; order count={len(rows)}; stock={stock_of(p1)}', ok, rows[0].id if rows else None
        register('Duplicate Transaction / Idempotent Retry', key1,
                 'Original order returned, no duplicate order or stock deduction', replay)

        def key_conflict():
            status, data = submit(p1, key1, qty=2)
            ok = status == 'Rejected — HTTP 409' and len(orders_for(key1)) == 1 and stock_of(p1) == 1
            return 'Rejected — Duplicate Transaction' if status == 'Rejected — HTTP 409' else status, str(data), ok, None
        register('Same Transaction Key with Changed Payload', key1,
                 'HTTP 409 and no second order', key_conflict)

        p2 = create_product(0)
        key2 = f'test-{run_id}-stock0'
        def insufficient():
            status, data = submit(p2, key2)
            ok = status == 'Rejected — HTTP 409' and not orders_for(key2) and stock_of(p2) == 0
            return 'Rolled Back — Insufficient Stock' if status == 'Rejected — HTTP 409' else status, f'{data}; stock={stock_of(p2)}; persisted orders={len(orders_for(key2))}', ok, None
        register('Out-of-Stock Transaction Rollback', key2,
                 'HTTP 409, no order persisted, stock unchanged', insufficient)

        p3 = create_product(1)
        key_a, key_b = f'test-{run_id}-race-a', f'test-{run_id}-race-b'
        def race():
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(submit, p3, key) for key in (key_a, key_b)]
                results = [f.result(timeout=20) for f in futures]
            statuses = [x[0] for x in results]
            succeeded = sum(x == 'Completed' for x in statuses)
            rejected = sum(x == 'Rejected — HTTP 409' for x in statuses)
            rows = len(orders_for(key_a)) + len(orders_for(key_b))
            ok = succeeded == 1 and rejected == 1 and rows == 1 and stock_of(p3) == 0
            return 'Completed + Rolled Back — Insufficient Stock' if ok else ', '.join(statuses), f'Outcomes={results}; persisted orders={rows}; final stock={stock_of(p3)}', ok, None
        register('Two Concurrent Checkouts for Last Stock Unit', f'{key_a} | {key_b}',
                 'Exactly one completed, one stock rejection, never negative stock', race)

        def card_checksum():
            valid = luhn_valid('4111111111111111') and not luhn_valid('4111111111111112')
            return 'Validation Completed', 'Synthetic test-only PANs; no payment details collected or charged', valid, None
        register('Card Number Luhn Checksum (Synthetic Test Data)', f'test-{run_id}-luhn',
                 'Known valid number accepted; invalid checksum rejected', card_checksum)
    finally:
        # Cleanup is transactional and limited to the exact test user and test product IDs.
        # Fail closed: unknown orders, Stripe references or other FK children stop deletion.
        if test_user_id is not None:
            with SessionFactory.begin() as s:
                recorded = list(s.scalars(select(Product).where(Product.id.in_(product_ids)))) if product_ids else []
                if len(recorded) != len(product_ids) or any(
                    p.category != 'Tests' or p.name != f'[CONCURRENCY TEST {run_id}]'
                    for p in recorded
                ):
                    raise RuntimeError('Cleanup refused: test product identity mismatch')
                test_orders = list(s.scalars(select(Order).where(Order.user_id == test_user_id)))
                order_ids = [o.id for o in test_orders]
                if order_ids:
                    items = list(s.scalars(select(OrderItem).where(OrderItem.order_id.in_(order_ids))))
                    if not items or any(item.product_id not in product_ids for item in items):
                        raise RuntimeError('Cleanup refused: order contains non-test products')
                    # Inspect ALL SQL Server FKs referencing the rows to be deleted;
                    # known internal OrderItems/Payments are removed explicitly below.
                    # Extra dependent rows (Stripe or new tables) must not be touched.
                    ids_csv = ','.join(str(int(x)) for x in order_ids)
                    references = s.execute(text('''
                        SELECT OBJECT_SCHEMA_NAME(fkc.parent_object_id) AS child_schema,
                               OBJECT_NAME(fkc.parent_object_id) AS child_table,
                               COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS child_column,
                               OBJECT_NAME(fkc.referenced_object_id) AS parent_table,
                               COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS parent_column
                        FROM sys.foreign_key_columns fkc
                        JOIN sys.foreign_keys fk ON fk.object_id=fkc.constraint_object_id
                        WHERE fk.is_disabled=0 AND OBJECT_NAME(fkc.referenced_object_id)
                              IN ('Users','Products','Orders')
                    ''')).mappings().all()
                    # Conservative allowlist based on the inspected MandaiDB schema.
                    allowed = {('dbo','OrderItems','OrderId','Orders','Id'),
                               ('dbo','Payments','OrderId','Orders','Id'),
                               ('dbo','OrderItems','ProductId','Products','Id'),
                               ('dbo','Orders','UserId','Users','Id')}
                    # Any additional FK dependency could block cleanup or affect records;
                    # refuse until explicitly audited, even if currently empty.
                    extras = [dict(r) for r in references if
                              (r['child_schema'], r['child_table'], r['child_column'],
                               r['parent_table'], r['parent_column']) not in allowed]
                    # Stripe schema references already observed: verify absence of child rows
                    # instead of rejecting simply because the foreign key exists.
                    for fk in extras:
                        schema = fk['child_schema']; table = fk['child_table']; column = fk['child_column']
                        parent = fk['parent_table']
                        if (schema, table, column, parent, fk['parent_column']) not in {
                            ('dbo','StripeCheckoutAttempts','OrderId','Orders','Id'),
                            ('dbo','StripeCheckoutAttempts','UserId','Users','Id'),
                            ('dbo','StripeTestAttempts','UserId','Users','Id')
                        }:
                            raise RuntimeError(f'Cleanup refused: unreviewed FK {fk}')
                        if parent == 'Orders': target = order_ids
                        elif parent == 'Users': target = [test_user_id]
                        else: target = product_ids
                        if target:
                            sql = f'SELECT COUNT_BIG(*) FROM [{schema}].[{table}] WHERE [{column}] IN (' + ','.join(str(int(x)) for x in target) + ')'
                            if s.scalar(text(sql)):
                                raise RuntimeError(f'Cleanup refused: dependent data in {schema}.{table}')
                    s.execute(delete(Payment).where(Payment.order_id.in_(order_ids)))
                    s.execute(delete(OrderItem).where(OrderItem.order_id.in_(order_ids)))
                    s.execute(delete(Order).where(Order.id.in_(order_ids), Order.user_id == test_user_id))
                if product_ids:
                    s.execute(delete(Product).where(Product.id.in_(product_ids), Product.category == 'Tests',
                                                    Product.name == f'[CONCURRENCY TEST {run_id}]'))
                s.execute(delete(User).where(User.id == test_user_id, User.email == user_email))
            with SessionFactory() as verify:
                if (verify.scalar(select(func.count()).select_from(User).where(User.id == test_user_id))
                    or (product_ids and verify.scalar(select(func.count()).select_from(Product).where(Product.id.in_(product_ids))))
                    or (order_ids and verify.scalar(select(func.count()).select_from(Order).where(Order.id.in_(order_ids))))):
                    raise RuntimeError('Cleanup verification failed; test records remain')
    return {'run_id': run_id, 'executed_at': start.isoformat(timespec='milliseconds'),
            'testing_status': 'PASS' if all(x['testing_status'] == 'PASS' for x in cases) else 'FAIL',
            'passed': sum(x['testing_status'] == 'PASS' for x in cases),
            'failed': sum(x['testing_status'] == 'FAIL' for x in cases),
            'results': cases}


@router.post('/api/admin/concurrency-tests')
def execute_concurrency_tests(db: Session = Depends(get_db), _admin: User = Depends(admin_only)):
    if os.getenv('ENABLE_CONCURRENCY_TESTS', 'false').lower() != 'true':
        raise HTTPException(404, 'Test suite is disabled')
    if not _running.acquire(blocking=False):
        raise HTTPException(409, 'A concurrency test is already running')
    try:
        return run_suite(db)
    finally:
        _running.release()
