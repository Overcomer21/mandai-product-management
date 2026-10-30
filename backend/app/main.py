import hashlib
import json
import logging
import os
import uuid
from decimal import Decimal
from fastapi import FastAPI, Depends, HTTPException, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, update, delete, exists, text
from sqlalchemy.exc import IntegrityError, OperationalError, SQLAlchemyError
from sqlalchemy.orm import Session
from .database import get_db
from .models import User,Product,Order,OrderItem,Payment
from .schemas import ProductInput,ProductOut,Login,PurchaseInput,PurchaseOut,CheckoutInput
from .security import current_user,admin_only,verify_password,issue_token
from .media_static import mount_product_media
from .login_guard import login_guard
from .stripe_test_router import router as stripe_test_router
from .stripe_checkout_router import router as stripe_checkout_router
from .stripe_payment_reconciliation import router as stripe_reconciliation_router
from .stripe_payment_return import router as stripe_payment_return_router
from .q5_test_launcher import router as q5_test_launcher_router
logger = logging.getLogger(__name__)
app=FastAPI(title='Mandai Merchandise Assessment API',version='1.0.0')
app.include_router(stripe_test_router)
app.include_router(stripe_checkout_router)
app.include_router(stripe_reconciliation_router)
app.include_router(stripe_payment_return_router)
app.include_router(q5_test_launcher_router)
mount_product_media(app)
app.add_middleware(CORSMiddleware,allow_origins=os.getenv('CORS_ORIGINS','http://localhost:3000,http://localhost:8080').split(','),allow_credentials=False,allow_methods=['GET','POST','PUT','DELETE'],allow_headers=['Authorization','Content-Type','Idempotency-Key'])

@app.get('/health')
def health():return {'status':'ok'}

@app.post('/api/auth/login')
def login(body: Login, request: Request, db: Session = Depends(get_db)):
    email = body.email.lower().strip()
    # For the single-process development API. Do not trust forwarded IP headers.
    client_ip = request.client.host if request.client else 'unknown'
    login_guard.check(email, client_ip)
    user = db.scalar(select(User).where(User.email == email))
    if not user or not verify_password(body.password, user.password_hash):
        login_guard.failure(email, client_ip)
        raise HTTPException(401, 'Invalid credentials')
    login_guard.success(email, client_ip)
    return {'access_token': issue_token(user), 'token_type': 'bearer', 'role': user.role}

@app.get('/api/account/me')
def current_account(user: User = Depends(current_user)):
    # Only the authenticated user's non-sensitive account fields are returned.
    return {
        'email': user.email,
        'delivery_address': user.delivery_address,
        'phone_number': user.phone_number,
        'payment_method': user.payment_method,
    }

@app.get('/api/products', response_model=list[ProductOut])
def catalog(db: Session = Depends(get_db)):
    # Use the injectable DB dependency so SQLite tests and production share the
    # same access path. Materialize DTOs before releasing the connection.
    try:
        products = db.scalars(
            select(Product).where(Product.is_active == True).order_by(Product.id)
        ).all()
        return [ProductOut.model_validate(product, from_attributes=True) for product in products]
    finally:
        # FastAPI's dependency finalizer will close it again (safe/idempotent).
        # Early close avoids holding the connection during response serialization.
        db.close()

@app.get('/api/products/{product_id}',response_model=ProductOut)
def product_detail(product_id:int,db:Session=Depends(get_db)):
    product=db.get(Product,product_id)
    if not product or not product.is_active:raise HTTPException(404,'Product not found')
    return product

@app.get('/api/admin/products',response_model=list[ProductOut])
def admin_list(db:Session=Depends(get_db),_admin:User=Depends(admin_only)):
    return db.scalars(select(Product).order_by(Product.id)).all()

@app.get('/api/admin/products/{product_id}',response_model=ProductOut)
def admin_detail(product_id:int,db:Session=Depends(get_db),_admin:User=Depends(admin_only)):
    product=db.get(Product,product_id)
    if not product:raise HTTPException(404,'Product not found')
    return product

@app.post('/api/admin/products',response_model=ProductOut,status_code=201)
def create_product(body:ProductInput,db:Session=Depends(get_db),_admin:User=Depends(admin_only)):
    product=Product(**body.model_dump())
    db.add(product);db.commit();db.refresh(product)
    return product

@app.put('/api/admin/products/{product_id}',response_model=ProductOut)
def edit_product(product_id:int,body:ProductInput,db:Session=Depends(get_db),_admin:User=Depends(admin_only)):
    product=db.get(Product,product_id)
    if not product:raise HTTPException(404,'Product not found')
    for key,val in body.model_dump().items():setattr(product,key,val)
    db.commit();db.refresh(product)
    return product

@app.delete('/api/admin/products/{product_id}')
def delete_product(product_id: int, db: Session = Depends(get_db), _admin: User = Depends(admin_only)):
    # A SQL Core DELETE avoids ORM relationship cascade behavior. SQL Server
    # foreign keys must be enabled and configured NO ACTION to protect orders.
    try:
        result = db.execute(delete(Product).where(Product.id == product_id))
        if result.rowcount == 0:
            db.rollback()
            raise HTTPException(status_code=404, detail='Product not found')
        db.commit()
        return {'deleted': True, 'deactivated': False, 'action': 'deleted'}
    except IntegrityError as exc:
        db.rollback()
        logger.warning('DELETE product_id=%s rejected by database constraint', product_id, exc_info=True)
        # SQL Server error 547 is a foreign-key/reference constraint violation.
        original = getattr(exc, 'orig', None)
        diagnostics = ' '.join(str(item) for item in getattr(original, 'args', ()))
        if '547' in diagnostics:
            raise HTTPException(
                status_code=409,
                detail='Unable to delete product. This product has existing transactions or related records and cannot be deleted.',
            ) from exc
        raise HTTPException(
            status_code=409,
            detail='Unable to delete product because a database integrity constraint was violated.',
        ) from exc
    except HTTPException:
        raise
    except SQLAlchemyError as exc:
        db.rollback()
        logger.exception('DELETE product_id=%s failed during SQL execution', product_id)
        raise HTTPException(status_code=500, detail='Database error while deleting product.') from exc

def order_response(order:Order,replayed=False):
    item=order.items[0]
    return PurchaseOut(order_id=order.id,product_id=item.product_id,quantity=item.quantity,total_amount=order.total_amount,status=order.status,replayed=replayed)

@app.post('/api/purchases',response_model=PurchaseOut,status_code=201)
def buy(body:PurchaseInput,idempotency_key:str=Header(min_length=8,max_length=128,alias='Idempotency-Key'),db:Session=Depends(get_db),user:User=Depends(current_user)):
    if user.role != 'user':
        raise HTTPException(403, 'Only customers can purchase')
    fingerprint=hashlib.sha256(json.dumps(body.model_dump(),sort_keys=True).encode()).hexdigest()
    existing=db.scalar(select(Order).where(Order.user_id==user.id,Order.idempotency_key==idempotency_key))
    if existing:
        if existing.request_fingerprint!=fingerprint:raise HTTPException(409,'Idempotency key reused with different purchase')
        return order_response(existing,True)
    try:
        # A single database transaction contains idempotency claim, stock reduction, and order.
        # The unique order key protects simultaneous retries. Failed stock changes rollback.
        product=db.get(Product,body.product_id)
        if not product or not product.is_active:raise HTTPException(404,'Product not available')
        amount=product.price*body.quantity
        order=Order(user_id=user.id,idempotency_key=idempotency_key,request_fingerprint=fingerprint,total_amount=amount,status='completed')
        db.add(order);db.flush() # claim unique (UserId, IdempotencyKey) before stock deduction
        result=db.execute(update(Product).where(Product.id==body.product_id,Product.is_active==True,Product.stock>=body.quantity).values(stock=Product.stock-body.quantity))
        if result.rowcount!=1:
            db.rollback();raise HTTPException(409,'Insufficient stock')
        db.add(OrderItem(order_id=order.id,product_id=body.product_id,quantity=body.quantity,unit_price=product.price))
        db.commit()
        return PurchaseOut(order_id=order.id,product_id=body.product_id,quantity=body.quantity,total_amount=amount,status='completed')
    except IntegrityError:
        db.rollback()
        previous=db.scalar(select(Order).where(Order.user_id==user.id,Order.idempotency_key==idempotency_key))
        if previous and previous.request_fingerprint==fingerprint:return order_response(previous,True)
        raise HTTPException(409,'Idempotency conflict')
    except OperationalError:
        db.rollback()
        raise HTTPException(503,'Database temporarily busy; retry with the same Idempotency-Key')

@app.get('/api/orders/my')
def my_orders(db:Session=Depends(get_db),user:User=Depends(current_user)):
    orders=db.scalars(select(Order).where(Order.user_id==user.id).order_by(Order.id.desc())).all()
    return [{'id':o.id,'total_amount':str(o.total_amount),'status':o.status} for o in orders]


# Demo-only payment simulation; no card numbers, CVV or external charges.
# Payment and stock + order are committed in the SAME database transaction.
DELIVERY_FEE = Decimal('4.90')

@app.post('/api/checkout', status_code=201)
def checkout(body:CheckoutInput,
             idempotency_key:str=Header(min_length=8,max_length=128,alias='Idempotency-Key'),
             db:Session=Depends(get_db), user:User=Depends(current_user)):
    if user.role != 'user':
        raise HTTPException(403, 'Only customers can check out')
    normalized=[{'product_id':i.product_id,'quantity':i.quantity} for i in body.items]
    if len({i['product_id'] for i in normalized}) != len(normalized):
        raise HTTPException(422, 'Duplicate product IDs in cart')
    fingerprint=hashlib.sha256(json.dumps({
        'items':sorted(normalized,key=lambda i:i['product_id']),
        'delivery_address':body.delivery_address,
        'payment_method':body.payment_method,
        'simulate_decline':body.simulate_decline,
    },sort_keys=True).encode()).hexdigest()
    previous=db.scalar(select(Order).where(Order.user_id==user.id,Order.idempotency_key==idempotency_key))
    if previous:
        if previous.request_fingerprint!=fingerprint:
            raise HTTPException(409,'Idempotency key used with different checkout')
        payment=db.scalar(select(Payment).where(Payment.order_id==previous.id))
        return {'order_id':previous.id,'status':previous.status,'total_amount':str(previous.total_amount),
                'payment_status':payment.status if payment else 'unknown','replayed':True}
    if body.simulate_decline:
        raise HTTPException(402,'Demo payment declined; no charge, order or stock deduction')
    try:
        # Claim unique user + request id first, then conditionally decrement each product.
        # Sorted product IDs reduce deadlocks when multiple carts overlap.
        order=Order(user_id=user.id,idempotency_key=idempotency_key,
                    request_fingerprint=fingerprint,total_amount=Decimal('0.00'),status='completed',
                    delivery_address=body.delivery_address)
        db.add(order)
        db.flush()
        subtotal=Decimal('0.00')
        details=[]
        for item in sorted(normalized,key=lambda i:i['product_id']):
            product=db.get(Product,item['product_id'])
            if product is None or not product.is_active:
                db.rollback();raise HTTPException(404,'Product no longer available')
            result=db.execute(update(Product).where(
                Product.id==product.id,Product.is_active==True,Product.stock>=item['quantity']
            ).values(stock=Product.stock-item['quantity']))
            if result.rowcount!=1:
                db.rollback();raise HTTPException(409,f'Insufficient stock for product {product.id}')
            # price sourced from backend database; no price accepted from the client
            subtotal+=product.price*item['quantity']
            details.append(OrderItem(order_id=order.id,product_id=product.id,
                                     quantity=item['quantity'],unit_price=product.price))
        order.total_amount=subtotal+DELIVERY_FEE
        db.add_all(details)
        db.add(Payment(order_id=order.id,method=body.payment_method,
                       provider_reference='DEMO-'+uuid.uuid4().hex,
                       card_last4='4242' if body.payment_method=='card_demo' else None,
                       amount=order.total_amount,status='approved_demo'))
        db.commit()
        return {'order_id':order.id,'status':'completed','subtotal':str(subtotal),
                'delivery_fee':str(DELIVERY_FEE),'total_amount':str(order.total_amount),
                'payment_status':'approved_demo','replayed':False}
    except IntegrityError:
        db.rollback()
        existing=db.scalar(select(Order).where(Order.user_id==user.id,Order.idempotency_key==idempotency_key))
        if existing and existing.request_fingerprint==fingerprint:
            payment=db.scalar(select(Payment).where(Payment.order_id==existing.id))
            return {'order_id':existing.id,'status':existing.status,'total_amount':str(existing.total_amount),
                    'payment_status':payment.status if payment else 'unknown','replayed':True}
        raise HTTPException(409,'Checkout idempotency conflict')
    except OperationalError:
        db.rollback()
        raise HTTPException(503,'Database busy, retry with same Idempotency-Key')

@app.get('/api/orders/my/details')
def order_details(db:Session=Depends(get_db),user:User=Depends(current_user)):
    orders=db.scalars(select(Order).where(Order.user_id==user.id).order_by(Order.id.desc())).all()
    result=[]
    for order in orders:
        payment=db.scalar(select(Payment).where(Payment.order_id==order.id))
        result.append({'id':order.id,'total_amount':str(order.total_amount),
                       'status':order.status,'payment_status':payment.status if payment else 'not_recorded',
                       'payment_method':payment.method if payment else None,
                       'items':[{'product_id':i.product_id,'name':db.get(Product,i.product_id).name,
                                 'quantity':i.quantity,'unit_price':str(i.unit_price)} for i in order.items]})
    return result


@app.get('/api/admin/testing/report')
def test_report(_admin: User = Depends(admin_only)):
    """Read-only results generated by the local CI/test runner; never execute commands via HTTP."""
    from pathlib import Path
    report_path = Path(os.getenv('MANDAI_TEST_REPORT_PATH', str(Path(__file__).resolve().parents[2] / 'test-results' / 'summary.json')))
    if not report_path.is_file():
        return {'generated_at': None, 'suites': [], 'message': 'No verified test results yet. Run scripts/run_tests.ps1 on a test environment.'}
    try:
        with report_path.open('r', encoding='utf-8') as handle:
            report = json.load(handle)
        if not isinstance(report, dict) or not isinstance(report.get('suites'), list):
            raise ValueError('Malformed report')
        return report
    except (OSError, ValueError) as error:
        raise HTTPException(503, 'Test report unavailable or invalid') from error
