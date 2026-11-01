import hashlib
import json
import logging
import os
import uuid
from decimal import Decimal
from fastapi import FastAPI, APIRouter, Depends, HTTPException, Header, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, update, delete, exists, text, or_, func, case
from sqlalchemy.exc import IntegrityError, OperationalError, SQLAlchemyError
from sqlalchemy.orm import Session, selectinload
from ...database import get_db
from ...models import User, Product, Order, OrderItem, Payment
from ...schemas import ProductInput, ProductOut, Login, PurchaseInput, PurchaseOut, CheckoutInput
from ...security import current_user, admin_only, verify_password, issue_token
from ...login_guard import login_guard
logger = logging.getLogger(__name__)
DELIVERY_FEE = Decimal('4.90')


def order_response(order:Order,replayed=False):
    item=order.items[0]
    return PurchaseOut(order_id=order.id,product_id=item.product_id,quantity=item.quantity,total_amount=order.total_amount,status=order.status,replayed=replayed)

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

def my_orders(db:Session=Depends(get_db),user:User=Depends(current_user)):
    orders=db.scalars(select(Order).where(Order.user_id==user.id).order_by(Order.id.desc())).all()
    return [{'id':o.id,'total_amount':str(o.total_amount),'status':o.status} for o in orders]

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

def order_details(db:Session=Depends(get_db),user:User=Depends(current_user)):
    # Fetch related items in batches instead of triggering a query per order.
    orders=db.scalars(select(Order).where(Order.user_id==user.id)
                      .options(selectinload(Order.items)).order_by(Order.id.desc())).all()
    if not orders:
        return []

    # Chunk IN lists for SQL Server's 2,100-parameter limit. The response contract
    # and ordering remain identical to the original endpoint.
    def chunks(values, size=1000):
        for start in range(0, len(values), size):
            yield values[start:start + size]

    order_ids=[order.id for order in orders]
    payments={}
    for batch in chunks(order_ids):
        payments.update({payment.order_id: payment for payment in
                         db.scalars(select(Payment).where(Payment.order_id.in_(batch))).all()})

    product_ids=list({item.product_id for order in orders for item in order.items})
    products={}
    for batch in chunks(product_ids):
        products.update({product.id: product for product in
                         db.scalars(select(Product).where(Product.id.in_(batch))).all()})

    result=[]
    for order in orders:
        payment=payments.get(order.id)
        result.append({'id':order.id,'total_amount':str(order.total_amount),
                       'status':order.status,'payment_status':payment.status if payment else 'not_recorded',
                       'payment_method':payment.method if payment else None,
                       'items':[{'product_id':i.product_id,'name':products.get(i.product_id).name,
                                 'quantity':i.quantity,'unit_price':str(i.unit_price)} for i in order.items]})
    return result
