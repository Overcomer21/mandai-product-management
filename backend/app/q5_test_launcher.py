"""Development-only launcher for existing fixed Q5 test script.
No user-supplied commands, database URLs, or suite selections are accepted.
SQL Server write/concurrency diagnostic is deliberately NOT part of this UI job.
"""
import json
import uuid
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
# Shared across Uvicorn workers on this local development machine.
STATE_PATH = ROOT / 'test-results' / 'q5_ui_state.json'
LOCK_PATH = ROOT / 'test-results' / 'q5_ui_run.lock'


def _save_state(state):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    temp = STATE_PATH.with_name(f'{STATE_PATH.name}.{uuid.uuid4().hex}.tmp')
    try:
        temp.write_text(json.dumps(state), encoding='utf-8')
        os.replace(temp, STATE_PATH)
    finally:
        temp.unlink(missing_ok=True)


def _read_state():
    try:
        return json.loads(STATE_PATH.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {'state': 'idle', 'exit_code': None, 'error': None}


def _acquire_run_lock():
    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(str(LOCK_PATH), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return False
    with os.fdopen(fd, 'w', encoding='utf-8') as out:
        out.write(str(os.getpid()))
    return True



def _require_local(request: Request):
    if os.getenv('MANDAI_ENABLE_UI_TEST_RUNNER') != '1':
        raise HTTPException(404, 'Development test launcher disabled')
    peer = request.client.host if request.client else ''
    if peer not in ('127.0.0.1', '::1'):
        raise HTTPException(403, 'Local API requests only')
    if not (ROOT / 'scripts' / 'run_tests.py').is_file():
        raise HTTPException(503, 'scripts/run_tests.py missing')


def _snapshot():
    result = _read_state()
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
        _save_state({'state': 'completed' if done.returncode == 0 else 'failed',
                     'exit_code': done.returncode, 'error': None})
    except (OSError, subprocess.TimeoutExpired) as exc:
        _save_state({'state': 'failed', 'exit_code': None, 'error': str(exc)[:300]})
    finally:
        LOCK_PATH.unlink(missing_ok=True)


@router.post('/run-all', status_code=202)
def run_all(request: Request, _admin: User = Depends(admin_only)):
    _require_local(request)
    base_url = os.getenv('MANDAI_UI_TEST_BASE_URL', 'http://127.0.0.1:8000')
    parsed = urlparse(base_url)
    if (parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost')
            or parsed.username or parsed.password or parsed.path not in ('', '/')
            or parsed.query or parsed.fragment):
        raise HTTPException(503, 'Invalid local MANDAI_UI_TEST_BASE_URL')
    if not _acquire_run_lock():
        raise HTTPException(409, 'Run All Test already in progress')
    _save_state({'state': 'running', 'exit_code': None, 'error': None})
    # Detach from HTTP request; status is available via GET /run-all/status.
    thread = threading.Thread(target=_execute, args=(base_url,), daemon=True)
    try:
        thread.start()
    except Exception:
        LOCK_PATH.unlink(missing_ok=True)
        raise
    return {'state': 'running', 'message': 'Running Q5 regression suites (SQL write tests excluded)'}


@router.get('/run-all/status')
def run_all_status(request: Request, _admin: User = Depends(admin_only)):
    _require_local(request)
    return _snapshot()
