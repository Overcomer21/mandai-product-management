"""Optional SQL Server Q5 concurrency evidence on MandaiDB; scoped disposable rows.
Run only with explicit opt-in. Do not call external Stripe endpoints.
"""
import json
import os
from pathlib import Path
import sys
from sqlalchemy import text, select, func

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))


def main():
    if os.environ.get('MANDAI_Q5_ALLOW_SQL_WRITES') != 'YES':
        raise SystemExit('BLOCKED: set MANDAI_Q5_ALLOW_SQL_WRITES=YES explicitly to allow disposable SQL writes')
    from app.database import SessionLocal, engine
    from app.models import User, Product, Order
    from app.concurrency_test_runner import run_suite
    if engine.dialect.name != 'mssql':
        raise SystemExit('BLOCKED: SQL Server connection required')
    with engine.connect() as connection:
        actual = connection.execute(text('SELECT DB_NAME()')).scalar_one()
    if actual != 'MandaiDB':
        raise SystemExit(f'BLOCKED: connected database {actual!r}; expected MandaiDB')
    if not os.environ.get('JWT_SECRET'):
        # This runner calls in-process checkout, not HTTP authentication; explicit config
        # still guards against accidentally running with a misconfigured environment.
        print('Note: in-process concurrency diagnostic does not require JWT authentication.')
    with SessionLocal() as db:
        result = run_suite(db)
    run_id = result['run_id']
    with SessionLocal() as db:
        users = db.scalar(select(func.count(User.id)).where(User.email == f'concurrency-test-{run_id}@example.invalid'))
        products = db.scalar(select(func.count(Product.id)).where(Product.name == f'[CONCURRENCY TEST {run_id}]'))
        orders = db.scalar(select(func.count(Order.id)).where(Order.idempotency_key.like(f'test-{run_id}-%')))
    result['cleanup_verified'] = not (users or products or orders)
    result['cleanup_remaining'] = {'users':users,'products':products,'orders':orders}
    out = ROOT/'test-results'/'q5_sqlserver_concurrency.json'
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({'testing_status':result['testing_status'],'passed':result['passed'],
                      'failed':result['failed'],'cleanup_verified':result['cleanup_verified'],
                      'report':str(out)},indent=2))
    return 0 if result['testing_status']=='PASS' and result['cleanup_verified'] and result['passed']==6 else 1

if __name__ == '__main__':
    sys.exit(main())
