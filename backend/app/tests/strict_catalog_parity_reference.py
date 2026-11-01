import importlib, shutil
from pathlib import Path
from fastapi.testclient import TestClient
from test_strict_parity import load

CASES = [
 '/api/products?limit=1&offset=0',
 '/api/products?limit=2&offset=2',
 '/api/products?limit=100&offset=0',
 '/api/products?sort=Name&limit=3',
 '/api/products?sort=Price%20low&limit=3',
 '/api/products?sort=Price%20high&limit=3',
 '/api/products?category=All',
 '/api/products?category=Apparel',
 '/api/products?category=Unknown',
 '/api/products?search=Product',
 '/api/products?search=%25',
 '/api/products?search=_',
 '/api/products?search=%5C',
 '/api/products?search=%20',
 '/api/products?in_stock=true',
 '/api/products/count?search=Product&in_stock=true',
 '/api/products/count?search=%25',
 '/api/products/categories',
 '/api/products/1',
 '/api/products/999',
 '/api/products?limit=101',
 '/api/products?offset=-1',
 '/api/admin/products?limit=2&offset=1',
]

def collect(mode):
    temp, mod, dbmodule, models, uid = load(mode)
    auth=importlib.import_module('reviewpkg.security')
    mod.app.dependency_overrides[auth.current_user]=lambda: type('U',(),{'id':uid,'role':'user'})()
    mod.app.dependency_overrides[auth.admin_only]=lambda: type('A',(),{'id':uid,'role':'admin'})()
    with TestClient(mod.app) as client:
        result=[(url, r.status_code, r.json()) for url in CASES for r in [client.get(url)]]
    shutil.rmtree(temp)
    return result

before=collect('original')
after=collect('refactor')
assert before==after, [(a,b) for a,b in zip(before,after) if a!=b]
print(f'CATALOG PARITY PASS {len(CASES)} GET scenarios; HTTP code and JSON identical')
