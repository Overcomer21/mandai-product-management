"""Execute available Mandai suites locally and publish truthful report for admin UI.
Usage from repository root: python scripts/run_tests.py
SQL Server write tests remain restricted to a dedicated test database. Read-only API stress tests can target a local API backed by MandaiDB.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from urllib.request import urlopen
from urllib.error import URLError, HTTPError
from urllib.parse import urlparse

def find_root():
    # Works both when installed at scripts/run_tests.py and when invoked from
    # a temporary directory alongside a checked-out project.
    script = Path(__file__).resolve()
    candidates = [script.parent.parent, script.parent, Path.cwd(), Path.cwd().parent]
    for candidate in candidates:
        if (candidate / 'backend').is_dir() and (candidate / 'frontend' / 'pubspec.yaml').is_file():
            return candidate
    # Retain canonical scripts/ layout even if the frontend has not been created.
    return script.parent.parent if script.parent.name.lower() == 'scripts' else script.parent

ROOT = find_root()
BACKEND = ROOT / 'backend'
FRONTEND = ROOT / 'frontend'
OUT = ROOT / 'test-results'

# Resolve the Windows Flutter batch launcher explicitly for subprocess.run.
FLUTTER = shutil.which('flutter.bat') or shutil.which('flutter')


def api_healthy(base_url):
    """Only check the local API; do not issue any writes or retry load tests."""
    try:
        with urlopen(base_url.rstrip('/') + '/health', timeout=3) as response:
            return response.status == 200
    except (URLError, HTTPError, OSError, TimeoutError, ValueError):
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stress-base-url', default='http://127.0.0.1:8000', help='Local FastAPI endpoint for read-only load tests')
    parser.add_argument('--skip-stress', action='store_true', help='Skip read-only API stress test')
    parser.add_argument('--no-api-preflight', action='store_true', help='Disable local API /health preflight (not recommended)')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    reports = []
    stress_stages = []
    # Fresh report: never leave yesterday's suites visible while a run starts.
    print(f'Project root: {ROOT}', flush=True)
    print(f'Backend: {BACKEND}; frontend: {FRONTEND}', flush=True)

    def skip(name, reason):
        reports.append(dict(name=name, status='NOT RUN', executed=False, exit_code=None, details=reason, passed=0, failed=0, skipped=0))
        publish()

    def run(name, cmd, cwd, *, env=None, junit=None):
        t = time.monotonic()
        logfile = OUT / (name.lower().replace(' ', '_').replace('/', '_') + '.log')
        try:
            if junit is not None:
                junit.unlink(missing_ok=True)  # never accept stale XML from a previous run
            with logfile.open('w', encoding='utf-8', errors='replace') as out:
                completed = subprocess.run(cmd, cwd=cwd, env=env, stdout=out, stderr=subprocess.STDOUT, timeout=900, check=False)
            code = completed.returncode
            parsed = {'passed': 0, 'failed': 0, 'skipped': 0}
            test_cases = []
            if junit and junit.exists():
                root = ET.parse(junit).getroot()
                cases = list(root.iter('testcase'))
                for case in cases:
                    failed = case.find('failure') is not None or case.find('error') is not None
                    skipped = case.find('skipped') is not None
                    test_cases.append({'name': case.get('name', ''),
                                       'group': case.get('classname', ''),
                                       'status': 'FAIL' if failed else ('SKIPPED' if skipped else 'PASS'),
                                       'duration_s': round(float(case.get('time', '0') or 0), 3),
                                       'message': ((case.find('failure') if case.find('failure') is not None else case.find('error')).get('message', '')[:300] if failed else '')})
                parsed = {'passed': sum(not any(c.find(x) is not None for x in ('failure', 'error', 'skipped')) for c in cases), 'failed': sum(c.find('failure') is not None or c.find('error') is not None for c in cases), 'skipped': sum(c.find('skipped') is not None for c in cases)}
            status = 'PASS' if code == 0 and (not junit or (junit.exists() and parsed['passed'] > 0)) else 'FAIL'
            reason = f'Exit {code}; {time.monotonic()-t:.1f}s; log: test-results/{logfile.name}'
            reports.append(dict(name=name, status=status, executed=True, exit_code=code, details=reason, test_cases=test_cases, **parsed))
        except (OSError, subprocess.TimeoutExpired, ET.ParseError) as e:
            logfile.write_text(str(e), encoding='utf-8')
            reports.append(dict(name=name, status='FAIL', executed=False, exit_code=None, details=f'Unable to execute: {e}', passed=0, failed=0, skipped=0))
        publish()

    def publish():
        payload = {'report_version': 2, 'scope': 'Mandai Question 5 only', 'stress_stages': stress_stages, 'generated_at': dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds'), 'suites': reports, 'summary': {'passed': sum(x['status']=='PASS' for x in reports), 'failed':sum(x['status']=='FAIL' for x in reports), 'not_run':sum(x['status']=='NOT RUN' for x in reports)}}
        temp = OUT / 'summary.json.tmp'
        temp.write_text(json.dumps(payload, indent=2), encoding='utf-8')
        temp.replace(OUT / 'summary.json')

    publish()
    # Explicitly exclude SQL Server integration tests from isolated SQLite runs.
    # Do not set MANDAI_SQLSERVER_TEST=1 for these tests.
    env = os.environ.copy()
    env.pop('MANDAI_SQLSERVER_TEST', None)
    # The existing conftest defaults to local SQLite on import. Force ephemeral scratch DB in backend.
    env['DATABASE_URL'] = 'sqlite:///' + str(OUT / 'pytest_bootstrap.db').replace('\\', '/')
    groups = {
        'Backend API CRUD and acceptance subset': ['tests/test_api.py', 'tests/test_media_mapping_verified.py'],
        'Backend checkout and transaction integrity': ['tests/test_checkout.py', 'tests/test_transaction_integrity.py'],
        'Backend security and authorization': ['tests/test_login_security.py', 'tests/test_purchase_role_security.py'],
        'Backend Question 5 API contract': ['tests/test_question5_contract.py'],
    }
    if not BACKEND.is_dir():
        for name in groups: skip(name, 'backend directory missing')
    else:
        for name, files in groups.items():
            missing = [f for f in files if not (BACKEND / f).is_file()]
            if missing: skip(name, 'Missing files: ' + ', '.join(missing)); publish(); continue
            xml = OUT / (name.lower().replace(' ', '_') + '.xml')
            run(name, [sys.executable, '-m', 'pytest', '-q', *files, f'--junitxml={xml}'], BACKEND, env=env, junit=xml)

    # Analyze Flutter separately; do not mark unavailable files as failed tests.
    if not FLUTTER:
        skip('Flutter static analysis', 'Flutter SDK not found in PATH')
        skip('Flutter unit and widget tests', 'Flutter SDK not found in PATH')
    elif not (FRONTEND / 'pubspec.yaml').is_file():
        skip('Flutter static analysis', f'frontend/pubspec.yaml missing under {FRONTEND}')
        skip('Flutter unit and widget tests', f'frontend/pubspec.yaml missing under {FRONTEND}')
    else:
        run('Flutter static analysis', [FLUTTER, 'analyze'], FRONTEND)
        if not (FRONTEND / 'test').is_dir() or not list((FRONTEND / 'test').rglob('*_test.dart')):
            skip('Flutter unit and widget tests', 'No frontend/test/*_test.dart files found')
        else:
            ordinary_tests = sorted(str(p.relative_to(FRONTEND)).replace('\\', '/') for p in (FRONTEND / 'test').rglob('*_test.dart') if p.name != 'question5_api_contract_test.dart')
            if ordinary_tests:
                run('Flutter unit and widget tests', [FLUTTER, 'test', '--coverage', *ordinary_tests], FRONTEND)
            else:
                skip('Flutter unit and widget tests', 'No non-contract Flutter test files')

    # Question 5 Flutter API contract (mocked HTTP, no MandaiDB writes).
    q5_flutter = FRONTEND / 'test' / 'question5_api_contract_test.dart'
    if not FLUTTER:
        skip('Flutter Question 5 API contract', 'Flutter CLI unavailable')
    elif not (FRONTEND / 'pubspec.yaml').is_file():
        skip('Flutter Question 5 API contract', 'frontend/pubspec.yaml missing')
    elif not q5_flutter.is_file():
        skip('Flutter Question 5 API contract', 'Missing frontend/test/question5_api_contract_test.dart')
    else:
        run('Flutter Question 5 API contract', [FLUTTER, 'test', 'test/question5_api_contract_test.dart'], FRONTEND)

    # Read-only local HTTP GET stress verification. Does not write any SQL rows.
    stress_script = ROOT / 'backend' / 'mandai_stress_test.py'
    if args.skip_stress:
        skip('Read-only API stress test', 'Disabled by --skip-stress')
    elif not stress_script.is_file():
        skip('Read-only API stress test', 'backend/mandai_stress_test.py not found')
    else:
        stress_json = OUT / 'stress-test-results.json'
        stress_json.unlink(missing_ok=True)
        endpoint = urlparse(args.stress_base_url)
        if not args.no_api_preflight and (endpoint.scheme != 'http' or endpoint.hostname not in ('localhost', '127.0.0.1') or endpoint.username or endpoint.password):
            skip('Read-only API stress test', 'Invalid URL: only local http://localhost or http://127.0.0.1 is allowed')
        elif not args.no_api_preflight and not api_healthy(args.stress_base_url):
            skip('Read-only API stress test', f'API not reachable or unhealthy at {args.stress_base_url.rstrip("/")}/health; verify FastAPI port')
        else:
            run('Read-only API stress test', [sys.executable, str(stress_script),
                 '--base-url', args.stress_base_url, '--endpoint', '/api/products',
                 '--output', str(stress_json)], BACKEND)
            # The command exit code is trustworthy, but check the actual report too.
            report = reports[-1]
            if report['status'] == 'PASS':
                try:
                    raw = json.loads(stress_json.read_text(encoding='utf-8'))
                    if raw.get('overall_pass') is not True or raw.get('endpoint') != '/api/products':
                        raise ValueError('Stress results not PASS or wrong endpoint')
                    report['details'] += '; verified JSON overall_pass=true, endpoint=/api/products'
                    stress_stages.clear()
                    for stage in raw.get('stages', []):
                        stress_stages.append({key: stage.get(key) for key in
                                              ('concurrency', 'requests', 'success', 'errors', 'error_rate_pct', 'throughput_rps', 'latency_ms', 'pass')})
                except (OSError, ValueError, json.JSONDecodeError) as exc:
                    report['status'] = 'FAIL'
                    report['details'] += f'; report verification error: {exc}'
                publish()
    # SQL Server write concurrency is a separate manually confirmed diagnostic.
    # Do not include its prior PASS in this run's passed count.
    prior = OUT / 'q5-sqlserver-concurrency.json'
    if prior.is_file():
        try:
            prior_data = json.loads(prior.read_text(encoding='utf-8'))
            prior_pass = (prior_data.get('status') == 'PASS' or prior_data.get('testing_status') == 'PASS') and prior_data.get('failed') == 0 and prior_data.get('passed') == 6
            previously_verified = {'status': 'PREVIOUSLY VERIFIED' if prior_pass else 'UNVERIFIED',
                                   'passed': prior_data.get('passed'), 'failed': prior_data.get('failed'),
                                   'run_id': prior_data.get('run_id'),
                                   'executed_at': prior_data.get('executed_at'),
                                   'test_cases': prior_data.get('results', []),
                                   'source': 'test-results/q5-sqlserver-concurrency.json',
                                   'note': 'Separate SQL Server write diagnostic; NOT executed by Run All Test'}
        except (ValueError, OSError, TypeError):
            previously_verified = {'status': 'UNVERIFIED', 'note': 'Prior concurrency report could not be parsed'}
    else:
        previously_verified = {'status': 'NOT AVAILABLE', 'note': 'No prior SQL concurrency report; not executed automatically'}
    report_path = OUT / 'summary.json'
    payload = json.loads(report_path.read_text(encoding='utf-8'))
    payload['previously_verified_sqlserver_concurrency'] = previously_verified
    suite_by_name = {s['name']: s for s in reports}
    def ac(label, title, required, note):
        observed = [suite_by_name.get(n) for n in required]
        complete = all(s is not None and s['status'] == 'PASS' for s in observed)
        failed = any(s is not None and s['status'] == 'FAIL' for s in observed)
        return {'id': label, 'requirement': title,
                'status': 'FAIL' if failed else ('PASS' if complete else 'NOT VERIFIED'),
                'evidence': required, 'note': note}
    payload['acceptance_criteria'] = [
        ac('AC01', 'Full-stack application / API contract',
           ['Backend Question 5 API contract', 'Flutter Question 5 API contract'],
           'Contract tests include mocked Flutter HTTP; not a live UI end-to-end test.'),
        ac('AC02', 'Backend product API',
           ['Backend API CRUD and acceptance subset', 'Backend Question 5 API contract'],
           'Product catalogue, details and API CRUD responses.'),
        ac('AC03', 'Admin inventory management',
           ['Backend API CRUD and acceptance subset', 'Backend security and authorization'],
           'Admin CRUD and authorization verified via API; dashboard interaction not fully automated.'),
        ac('AC04', 'Customer storefront and buy',
           ['Backend Question 5 API contract', 'Backend checkout and transaction integrity'],
           'Storefront contract and purchase API; live browser journey not fully automated.'),
        ac('AC05', 'Role-based admin CRUD',
           ['Backend API CRUD and acceptance subset', 'Backend security and authorization'],
           'Guest/customer denied; admin allowed.'),
        ac('AC06', 'Secure purchase, transaction safety and overselling',
           ['Backend checkout and transaction integrity', 'Backend Question 5 API contract'],
           'SQLite regression checked in this run; SQL Server concurrency is separately verified.'),
    ]
    payload['acceptance_criteria'][5]['sqlserver_concurrency_evidence'] = previously_verified['status']
    temp = OUT / 'summary.json.tmp'
    temp.write_text(json.dumps(payload, indent=2), encoding='utf-8')
    temp.replace(report_path)
    print(json.dumps(json.loads((OUT/'summary.json').read_text(encoding='utf-8'))['summary'], indent=2))
    return 1 if any(x['status']=='FAIL' for x in reports) else 0


if __name__ == '__main__':
    sys.exit(main())
