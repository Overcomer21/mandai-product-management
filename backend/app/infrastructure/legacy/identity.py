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

def current_account(user: User = Depends(current_user)):
    # Only the authenticated user's non-sensitive account fields are returned.
    return {
        'email': user.email,
        'delivery_address': user.delivery_address,
        'phone_number': user.phone_number,
        'payment_method': user.payment_method,
    }
