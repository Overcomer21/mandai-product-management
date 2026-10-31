"""Opt-in SQL Server checkout concurrency diagnostic. Place in project scripts/.
Uses disposable MandaiDB entities only; no Stripe or master-product modifications.
Run: python scripts/run_q5_100_buyers.py --confirm-mandaidb-tests-only
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from decimal import Decimal
import json
from pathlib import Path
import sys
import time
import uuid

from sqlalchemy import select, func, delete, text
from sqlalchemy.orm import sessionmaker

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--confirm-mandaidb-tests-only', action='store_true', required=True)
    ap.add_argument('--iterations', type=int, default=10)
    ap.add_argument('--buyers', type=int, default=100)
    ap.add_argument('--stock', type=int, default=30)
    ap.add_argument('--delay', type=float, default=5)
    args = ap.parse_args()
    if not (1 <= args.iterations <= 10 and 1 <= args.buyers <= 100 and 1 <= args.stock < args.buyers):
        ap.error('Limits: 1-10 iterations, 1-100 buyers, 1 <= stock < buyers')

    from app.database import engine
    from app.models import User, Product, Order, OrderItem, Payment
    from app.schemas import CheckoutInput
    from app.main import checkout
    from fastapi import HTTPException

    if engine.dialect.name != 'mssql':
        raise SystemExit('REFUSED: SQL Server required')
    with engine.connect() as c:
        dbname = c.scalar(text('SELECT DB_NAME()'))
    if dbname != 'MandaiDB':
        raise SystemExit(f'REFUSED: expected MandaiDB, got {dbname!r}')

    Session = sessionmaker(bind=engine, expire_on_commit=False)
    run_id = uuid.uuid4().hex[:12]
    email = f'concurrency-test-{run_id}@example.invalid'
    name = f'[CONCURRENCY TEST {run_id}]'
    user_id = None
    product_ids = []
    results = []
    cleanup_verified = False
    cleanup_error = None
    report = ROOT / 'test-results' / 'q5-100-buyers-concurrency.json'
    report.parent.mkdir(parents=True, exist_ok=True)

    def attempt(pid, uid, key, gate):
        gate.wait()
        try:
            with Session() as s:
                user = s.get(User, uid)
                body = CheckoutInput(items=[{'product_id': pid, 'quantity': 1}],
                                     delivery_address='Automated integration test only',
                                     payment_method='card_demo', simulate_decline=False)
                try:
                    response = checkout(body=body, idempotency_key=key, db=s, user=user)
                    return ('success', response.get('order_id'))
                except HTTPException as e:
                    s.rollback()
                    return ('out_of_stock' if e.status_code == 409 and 'Insufficient stock' in str(e.detail) else 'http_error', e.status_code)
                except Exception as e:
                    s.rollback()
                    return ('error', type(e).__name__ + ': ' + str(e)[:180])
        except Exception as e:
            return ('error', type(e).__name__ + ': ' + str(e)[:180])

    try:
        with Session.begin() as s:
            u = User(email=email, password_hash='DISABLED-TEST-ACCOUNT', role='user')
            s.add(u)
            s.flush()
            user_id = u.id
        for iteration in range(1, args.iterations + 1):
            with Session.begin() as s:
                p = Product(name=name, description='Disposable load test item', category='Tests',
                            price=Decimal('7.00'), stock=args.stock, is_active=True)
                s.add(p)
                s.flush()
                pid = p.id
                product_ids.append(pid)
            import threading
            gate = threading.Barrier(args.buyers + 1, timeout=60)
            started = time.perf_counter()
            with ThreadPoolExecutor(max_workers=args.buyers) as pool:
                futures = [pool.submit(attempt, pid, user_id, f'test-{run_id}-{iteration}-{n}', gate)
                           for n in range(args.buyers)]
                gate.wait()
                outcomes = [f.result() for f in as_completed(futures)]
            counts = Counter(k for k, _ in outcomes)
            with Session() as s:
                remaining = s.scalar(select(Product.stock).where(Product.id == pid))
                rows = s.execute(select(Order.id, OrderItem.quantity).join(OrderItem, OrderItem.order_id == Order.id)
                                 .where(Order.user_id == user_id, OrderItem.product_id == pid)).all()
                order_ids = [r[0] for r in rows]
                units = sum(r[1] for r in rows)
                payments = s.execute(select(Payment.order_id, Payment.status).where(Payment.order_id.in_(order_ids))).all() if order_ids else []
                payment_ids = [x[0] for x in payments]
            ok = (counts['success'] == args.stock and counts['out_of_stock'] == args.buyers-args.stock
                  and sum(counts.values()) == args.buyers and remaining == 0 and units == args.stock
                  and len(rows) == args.stock and len(set(order_ids)) == args.stock
                  and len(payments) == args.stock and len(set(payment_ids)) == args.stock
                  and all(x[1] == 'approved_demo' for x in payments))
            record = {'iteration': iteration, 'status': 'PASS' if ok else 'FAIL', 'buyers': args.buyers,
                      'initial_stock': args.stock, 'outcomes': dict(counts), 'remaining_stock': remaining,
                      'persisted_orders': len(rows), 'sold_units': units, 'approved_demo_payments': len(payments),
                      'elapsed_seconds': round(time.perf_counter()-started, 2),
                      'errors': [v for k,v in outcomes if k in ('error','http_error')][:10]}
            results.append(record)
            print(json.dumps(record), flush=True)
            if not ok:
                print('STOP: verification failed; no further iterations', flush=True)
                break
            if iteration < args.iterations:
                time.sleep(args.delay)
    finally:
        # Cleanup fails closed for unknown references. Never delete master rows.
        try:
            if user_id is not None:
                with Session.begin() as s:
                    products = s.scalars(select(Product).where(Product.id.in_(product_ids))).all() if product_ids else []
                    if len(products) != len(product_ids) or any(p.name != name or p.category != 'Tests' for p in products):
                        raise RuntimeError('Test product identity mismatch; cleanup refused')
                    user = s.get(User, user_id)
                    if user is None or user.email != email:
                        raise RuntimeError('Test user identity mismatch; cleanup refused')
                    orders = s.scalars(select(Order).where(Order.user_id == user_id)).all()
                    order_ids = [o.id for o in orders]
                    items = s.scalars(select(OrderItem).where(OrderItem.order_id.in_(order_ids))).all() if order_ids else []
                    if orders and (not items or any(i.product_id not in product_ids for i in items)):
                        raise RuntimeError('Unexpected order items; cleanup refused')
                    # Only known foreign keys may reference these rows.
                    fks = s.execute(text('''SELECT OBJECT_SCHEMA_NAME(fkc.parent_object_id) child_schema,
                        OBJECT_NAME(fkc.parent_object_id) child_table,
                        COL_NAME(fkc.parent_object_id,fkc.parent_column_id) child_column,
                        OBJECT_NAME(fkc.referenced_object_id) parent_table,
                        COL_NAME(fkc.referenced_object_id,fkc.referenced_column_id) parent_column
                        FROM sys.foreign_key_columns fkc JOIN sys.foreign_keys fk
                        ON fk.object_id=fkc.constraint_object_id
                        WHERE fk.is_disabled=0 AND OBJECT_NAME(fkc.referenced_object_id)
                        IN ('Users','Products','Orders')''')).mappings().all()
                    allowed = {('dbo','OrderItems','OrderId','Orders','Id'),('dbo','Payments','OrderId','Orders','Id'),
                               ('dbo','OrderItems','ProductId','Products','Id'),('dbo','Orders','UserId','Users','Id')}
                    stripe = {('dbo','StripeCheckoutAttempts','OrderId','Orders','Id'),
                              ('dbo','StripeCheckoutAttempts','UserId','Users','Id'),
                              ('dbo','StripeTestAttempts','UserId','Users','Id')}
                    for fk in fks:
                        key = tuple(fk[k] for k in ('child_schema','child_table','child_column','parent_table','parent_column'))
                        if key in allowed:
                            continue
                        if key not in stripe:
                            raise RuntimeError(f'Unreviewed foreign key: {key}; cleanup refused')
                        ids = order_ids if fk['parent_table'] == 'Orders' else [user_id]
                        if ids:
                            q = f"SELECT COUNT_BIG(*) FROM [{fk['child_schema']}].[{fk['child_table']}] WHERE [{fk['child_column']}] IN (" + ','.join(str(int(i)) for i in ids) + ')'
                            if s.scalar(text(q)):
                                raise RuntimeError(f'Stripe dependent records present: {key}; cleanup refused')
                    if order_ids:
                        s.execute(delete(Payment).where(Payment.order_id.in_(order_ids)))
                        s.execute(delete(OrderItem).where(OrderItem.order_id.in_(order_ids)))
                        s.execute(delete(Order).where(Order.id.in_(order_ids), Order.user_id == user_id))
                    if product_ids:
                        s.execute(delete(Product).where(Product.id.in_(product_ids), Product.category == 'Tests', Product.name == name))
                    s.execute(delete(User).where(User.id == user_id, User.email == email))
                with Session() as s:
                    cleanup_verified = (s.get(User, user_id) is None and
                        all(s.get(Product, pid) is None for pid in product_ids) and
                        not s.scalar(select(func.count(Order.id)).where(Order.user_id == user_id)))
        except Exception as exc:
            cleanup_error = f'{type(exc).__name__}: {exc}'
        payload = {'run_id': run_id, 'database': 'MandaiDB', 'executed_at': datetime.now(timezone.utc).isoformat(),
                   'status': 'PASS' if len(results) == args.iterations and all(r['status']=='PASS' for r in results) and cleanup_verified else 'FAIL',
                   'cleanup_verified': cleanup_verified, 'cleanup_error': cleanup_error,
                   'iterations_completed': len(results), 'iterations_requested': args.iterations,
                   'results': results}
        report.write_text(json.dumps(payload, indent=2), encoding='utf-8')
        print('Report:', report, 'Status:', payload['status'], 'Cleanup:', cleanup_verified, flush=True)
    return 0 if payload['status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
