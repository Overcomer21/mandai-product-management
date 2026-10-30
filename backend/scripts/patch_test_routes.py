"""Minimal in-place patch on CURRENT backend/app/main.py; makes backup; preserves other edits."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
p = root / 'backend' / 'app' / 'main.py'
if not p.is_file():
    raise SystemExit(f'Missing {p}')
s = p.read_text(encoding='utf-8')
old = s
anchor = 'from .stripe_payment_return import router as stripe_payment_return_router'
if 'from .concurrency_test_runner import router as concurrency_test_router' not in s:
    if anchor not in s:
        raise SystemExit('Unrecognized main.py import layout. No modifications made.')
    s = s.replace(anchor, anchor + '\nfrom .concurrency_test_runner import router as concurrency_test_router', 1)
anchor2 = 'app.include_router(stripe_payment_return_router)'
if 'app.include_router(concurrency_test_router)' not in s:
    if anchor2 not in s:
        raise SystemExit('Unrecognized main.py router layout. No modifications made.')
    s = s.replace(anchor2, anchor2+'\napp.include_router(concurrency_test_router)',1)
# Replace report path if it uses relative default, allowing correct lookup irrespective of backend working directory.
needle = "Path(os.getenv('MANDAI_TEST_REPORT_PATH', 'test-results/summary.json'))"
replacement = "Path(os.getenv('MANDAI_TEST_REPORT_PATH', str(Path(__file__).resolve().parents[2] / 'test-results' / 'summary.json')))"
if needle in s:
    s = s.replace(needle,replacement,1)
if s == old:
    print('No changes necessary.')
else:
    backup = p.with_suffix('.py.before_testing_patch')
    if not backup.exists():
        shutil.copy2(p, backup)
    p.write_text(s, encoding='utf-8')
    print(f'Patched {p}; original backed up to {backup}')
