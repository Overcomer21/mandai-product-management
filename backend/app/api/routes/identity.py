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
from ...application.identity import IdentityService
from ...infrastructure.identity_adapter import IdentityAdapter
service = IdentityService(IdentityAdapter())
router_segment_1 = APIRouter()



@router_segment_1.post('/api/auth/login')
def login(body: Login, request: Request, db: Session=Depends(get_db)):
    return service.login(body=body, request=request, db=db)

@router_segment_1.get('/api/account/me')
def current_account(user: User=Depends(current_user)):
    return service.current_account(user=user)

