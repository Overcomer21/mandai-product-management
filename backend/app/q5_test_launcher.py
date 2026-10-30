"""Development-only launcher for existing fixed Q5 test script.
No user-supplied commands, database URLs, or suite selections are accepted.
SQL Server write/concurrency diagnostic is deliberately NOT part of this UI job.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
from urllib.parse import urlparse
from fastapi import APIRouter, Depends, HTTPException, Request
from .models import User
from .security import admin_only

router = APIRouter(prefix='/api/admin/testing', tags=['Development testing'])
ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / 'test-results' / 'summary.json'
LOCK = threading.Lock()
STATE_LOCK = threading.Lock()
STATE = {'state': 'idle', 'exit_code': None, 'error': None}


def _require_local(request: Request):
    if os.getenv('MANDAI_ENABLE_UI_TEST_RUNNER') != '1':
        raise HTTPException(404, 'Development test launcher disabled')
    peer = request.client.host if request.client else ''
    if peer not in ('127.0.0.1', '::1'):
        raise HTTPException(403, 'Local API requests only')
    if not (ROOT / 'scripts' / 'run_tests.py').is_file():
        raise HTTPException(503, 'scripts/run_tests.py missing')


def _snapshot():
    with STATE_LOCK:
        result = dict(STATE)
    if REPORT.is_file():
        try:
            report = json.loads(REPORT.read_text(encoding='utf-8'))
            if isinstance(report, dict) and isinstance(report.get('suites'), list):
                result['report'] = report
        except (OSError, ValueError):
            pass
    return result


def _execute(base_url):
    try:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        logfile = REPORT.parent / 'q5_ui_runall.log'
        env = os.environ.copy()
        # Never forward opt-in SQL Server write flags into the subprocess.
        for key in ('MANDAI_SQLSERVER_TEST', 'MANDAI_SQLSERVER_TEST_DATABASE_URL',
                    'API_TEST_BASE'):
            env.pop(key, None)
        cmd = [sys.executable, str(ROOT / 'scripts' / 'run_tests.py'),
               '--stress-base-url', base_url]
        with logfile.open('w', encoding='utf-8') as out:
            done = subprocess.run(cmd, cwd=str(ROOT), env=env, stdout=out,
                                  stderr=subprocess.STDOUT, timeout=1200, check=False)
        with STATE_LOCK:
            STATE.update(state='completed' if done.returncode == 0 else 'failed',
                         exit_code=done.returncode, error=None)
    except (OSError, subprocess.TimeoutExpired) as exc:
        with STATE_LOCK:
            STATE.update(state='failed', exit_code=None, error=str(exc)[:300])
    finally:
        LOCK.release()


@router.post('/run-all', status_code=202)
def run_all(request: Request, _admin: User = Depends(admin_only)):
    _require_local(request)
    base_url = os.getenv('MANDAI_UI_TEST_BASE_URL', 'http://127.0.0.1:8000')
    parsed = urlparse(base_url)
    if (parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost')
            or parsed.username or parsed.password or parsed.path not in ('', '/')
            or parsed.query or parsed.fragment):
        raise HTTPException(503, 'Invalid local MANDAI_UI_TEST_BASE_URL')
    if not LOCK.acquire(blocking=False):
        raise HTTPException(409, 'Run All Test already in progress')
    with STATE_LOCK:
        STATE.update(state='running', exit_code=None, error=None)
    # Detach from HTTP request; status is available via GET /run-all/status.
    thread = threading.Thread(target=_execute, args=(base_url,), daemon=True)
    try:
        thread.start()
    except Exception:
        LOCK.release()
        raise
    return {'state': 'running', 'message': 'Running Q5 regression suites (SQL write tests excluded)'}


@router.get('/run-all/status')
def run_all_status(request: Request, _admin: User = Depends(admin_only)):
    _require_local(request)
    return _snapshot()
