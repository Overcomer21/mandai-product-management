import sys, tempfile, shutil, pathlib, importlib, json, ast
from decimal import Decimal
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
BASE=pathlib.Path('/mnt/data')
R=BASE/'mandai_backend_clean_refactor'
orig=BASE/'main(20261101-030318).py'

def load(mode):
 t=pathlib.Path(tempfile.mkdtemp())
 pkg=t/'reviewpkg'
 shutil.copytree(R,pkg)
 if mode=='original':(pkg/'main.py').write_bytes(orig.read_bytes())
 (pkg/'database.py').write_text('''from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
engine=create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=__import__('sqlalchemy').pool.StaticPool)
Base=declarative_base()
SessionLocal=sessionmaker(bind=engine)
def get_db():
    with SessionLocal() as session: yield session
''')
 (pkg/'login_guard.py').write_text('''class Guard:
 def check(self,*args): pass
 def failure(self,*args): pass
 def success(self,*args): pass
login_guard=Guard()
''')
 (pkg/'q5_test_launcher.py').write_text('from fastapi import APIRouter\nrouter=APIRouter()\n')
 (t/'media'/'products').mkdir(parents=True)
 sys.path.insert(0,str(t))
 for key in list(sys.modules):
  if key=='reviewpkg' or key.startswith('reviewpkg.'):
   del sys.modules[key]
 mod=importlib.import_module('reviewpkg.main')
 dbmodule=importlib.import_module('reviewpkg.database')
 models=importlib.import_module('reviewpkg.models')
 dbmodule.Base.metadata.create_all(dbmodule.engine)
 with dbmodule.SessionLocal() as db:
  u=models.User(email='user@example.com',password_hash='hash',role='user')
  db.add(u);db.flush(); uid=u.id
  db.add_all([models.Product(name=f'Product {i}',description='Test',category='Apparel',price=Decimal('5.50'),stock=10,is_active=True,image_url='',spin_image_urls='') for i in range(5)])
  db.commit()
 return t,mod,dbmodule,models,uid

def snapshot(mode):
 t,mod,dbmodule,models,uid=load(mode)
 router=[(r.path,sorted(r.methods),r.name,getattr(r,'status_code',None),str(getattr(r,'response_model',None))) for r in mod.app.routes if hasattr(r,'methods')]
 auth=importlib.import_module('reviewpkg.security')
 mod.app.dependency_overrides[auth.current_user]=lambda: type('UserStub',(),{'id':uid,'role':'user'})()
 mod.app.dependency_overrides[auth.admin_only]=lambda: type('AdminStub',(),{'id':uid,'role':'admin'})()
 responses=[]
 with TestClient(mod.app) as c:
  for path in ['/health','/api/products/categories','/api/products/count','/api/products?category=Apparel&sort=Price%20low&limit=2&offset=1','/api/products/1','/api/admin/products?limit=2&offset=1','/api/admin/products/count','/api/admin/products/stats','/api/orders/my','/api/orders/my/details','/api/admin/testing/report']:
   r=c.get(path);responses.append((path,r.status_code,r.json()))
  for method,path,payload,key in [('POST','/api/purchases',{'product_id':1,'quantity':2},'purchase-test-key-01'),('POST','/api/purchases',{'product_id':1,'quantity':2},'purchase-test-key-01'),('POST','/api/checkout',{'items':[{'product_id':2,'quantity':1}],'delivery_address':'Test Address 123','payment_method':'card_demo','simulate_decline':True},'checkout-decline-01')]:
   r=c.request(method,path,json=payload,headers={'Idempotency-Key':key}); data=r.json(); data.pop('order_id',None) if False else None; responses.append((method,path,r.status_code,data))
  r=c.get('/api/products/1'); responses.append(('stock-after-purchase',r.status_code,r.json().get('stock')))
 shutil.rmtree(t)
 return router,responses

before=snapshot('original')
after=snapshot('refactor')
assert before==after, '\n'+str([(a,b) for a,b in zip(before[1],after[1]) if a!=b])
print('ROUTE AND HTTP PAYLOAD EQUIVALENCE PASS',len(before[0]),'registered routes,',len(before[1]),'requests')
