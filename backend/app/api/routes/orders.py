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
from ...application.orders import OrdersService
from ...infrastructure.orders_adapter import OrdersAdapter
service = OrdersService(OrdersAdapter())
router_segment_3 = APIRouter()



@router_segment_3.post('/api/purchases', response_model=PurchaseOut, status_code=201)
def buy(body: PurchaseInput, idempotency_key: str=Header(min_length=8, max_length=128, alias='Idempotency-Key'), db: Session=Depends(get_db), user: User=Depends(current_user)):
    return service.buy(body=body, idempotency_key=idempotency_key, db=db, user=user)

@router_segment_3.get('/api/orders/my')
def my_orders(db: Session=Depends(get_db), user: User=Depends(current_user)):
    return service.my_orders(db=db, user=user)

@router_segment_3.post('/api/checkout', status_code=201)
def checkout(body: CheckoutInput, idempotency_key: str=Header(min_length=8, max_length=128, alias='Idempotency-Key'), db: Session=Depends(get_db), user: User=Depends(current_user)):
    return service.checkout(body=body, idempotency_key=idempotency_key, db=db, user=user)

@router_segment_3.get('/api/orders/my/details')
def order_details(db: Session=Depends(get_db), user: User=Depends(current_user)):
    return service.order_details(db=db, user=user)

