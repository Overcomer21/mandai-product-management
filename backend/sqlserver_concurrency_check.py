"""Run only against dedicated SQL Server development DB with API already running."""
import os
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
import httpx
from sqlalchemy import select
from app.database import SessionLocal
from app.models import Product, Order, OrderItem

def main():
    if os.getenv('DATABASE_URL','').startswith('sqlite:'):
        raise RuntimeError('Requires real SQL Server, not SQLite')
    base=os.getenv('API_TEST_BASE','http://localhost:8000')
    pw=os.getenv('DEMO_USER_PASSWORD')
    if not pw:raise RuntimeError('Set DEMO_USER_PASSWORD in environment')
    with httpx.Client(timeout=30) as client:
        res=client.post(base+'/api/auth/login',json={'email':'user@demo.local','password':pw})
        res.raise_for_status()
        token=res.json()['access_token']
    with SessionLocal.begin() as db:
        product=Product(name='Concurrency Test '+uuid4().hex[:8],description='Isolated test product',category='Test',price=1,stock=10,is_active=True)
        db.add(product);db.flush();product_id=product.id
    prefix='race-'+uuid4().hex+'-'
    def worker(i):
        with httpx.Client(timeout=45) as client:
            return client.post(base+'/api/purchases',headers={'Authorization':f'Bearer {token}','Idempotency-Key':prefix+str(i)},json={'product_id':product_id,'quantity':1}).status_code
    with ThreadPoolExecutor(max_workers=20) as pool:
        statuses=list(pool.map(worker,range(20)))
    with SessionLocal() as db:
        remaining=db.get(Product,product_id).stock
        order_count=len(db.scalars(select(Order).join(OrderItem,Order.id==OrderItem.order_id).where(OrderItem.product_id==product_id)).all())
    print('statuses=',statuses,'stock=',remaining,'orders=',order_count)
    assert statuses.count(201)==10 and statuses.count(409)==10, 'Unexpected HTTP result counts'
    assert remaining==0 and order_count==10, 'Overselling or lost orders'
    print('PASS: SQL Server concurrent purchases did not oversell')

if __name__=='__main__':main()
