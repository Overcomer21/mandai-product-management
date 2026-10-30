"""Opt-in diagnostic on MandaiDB. Run from project root, backend on sys.path."""
import argparse
import json
import os
from pathlib import Path
import sys
from sqlalchemy import text

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--confirm-mandaidb-tests-only', action='store_true', required=True)
    args = parser.parse_args()
    if not args.confirm_mandaidb_tests_only:
        parser.error('Explicit confirmation required')
    from app.database import SessionLocal, engine
    from app.concurrency_test_runner import run_suite
    if engine.dialect.name != 'mssql':
        raise SystemExit('Refused: expected SQL Server.')
    with engine.connect() as connection:
        db_name = connection.scalar(text('SELECT DB_NAME()'))
    if db_name != 'MandaiDB':
        raise SystemExit(f'Refused: connected to {db_name!r}, expected MandaiDB.')
    with SessionLocal() as session:
        result = run_suite(session)
    out = ROOT / 'test-results' / 'q5-sqlserver-concurrency.json'
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'status': result['testing_status'], 'passed': result['passed'], 'failed': result['failed'],
                      'report': str(out)}, indent=2))
    return 0 if result['testing_status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
