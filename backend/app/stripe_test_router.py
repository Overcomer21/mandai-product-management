"""Optional Stripe test-mode payment session + verified webhook inbox.

This add-on NEVER marks an order paid, decreases stock, or exposes a live charge.
It intentionally leaves fulfilment to a separately designed pending-order workflow.
"""
import hashlib
import json
import os
from decimal import Decimal, ROUND_HALF_UP
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import select, UniqueConstraint, String, Integer, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, Session

from .database import Base, get_db
from .models import Product, User
from .security import current_user

router = APIRouter(prefix='/api/stripe-test', tags=['Stripe test-mode (optional)'])

class StripeTestAttempt(Base):
    __tablename__ = 'StripeTestAttempts'
    id: Mapped[int] = mapped_column('Id', Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column('UserId', Integer, nullable=False)
    idempotency_key: Mapped[str] = mapped_column('IdempotencyKey', String(128), nullable=False)
    fingerprint: Mapped[str] = mapped_column('Fingerprint', String(64), nullable=False)
    session_id: Mapped[str] = mapped_column('SessionId', String(255), unique=True, nullable=False)
    checkout_url: Mapped[str] = mapped_column('CheckoutUrl', String(2048), nullable=False)
    status: Mapped[str] = mapped_column('Status', String(30), nullable=False, default='pending')
    amount_minor: Mapped[int] = mapped_column('AmountMinor', Integer, nullable=False)
    created_at = mapped_column('CreatedAt', DateTime(timezone=True), server_default=func.current_timestamp())
    __table_args__ = (UniqueConstraint('UserId', 'IdempotencyKey', name='UQ_StripeTestAttempts_User_Key'),)

class StripeWebhookEvent(Base):
    __tablename__ = 'StripeTestWebhookEvents'
    id: Mapped[int] = mapped_column('Id', Integer, primary_key=True)
    event_id: Mapped[str] = mapped_column('EventId', String(255), unique=True, nullable=False)
    event_type: Mapped[str] = mapped_column('EventType', String(100), nullable=False)
    created_at = mapped_column('CreatedAt', DateTime(timezone=True), server_default=func.current_timestamp())

class StripeTestItem(BaseModel):
    product_id: int = Field(gt=0)
    quantity: int = Field(gt=0, le=100)

class StripeTestCart(BaseModel):
    items: list[StripeTestItem] = Field(min_length=1, max_length=30)


def _require_test_key():
    key = os.getenv('STRIPE_SECRET_KEY', '')
    if not key.startswith('sk_test_'):
        raise HTTPException(503, 'Stripe test mode is not configured')
    return key


def _stripe():
    try:
        import stripe
    except ImportError as exc:
        raise HTTPException(503, 'Stripe Python package is not installed') from exc
    return stripe


def _safe_redirect(var):
    url = os.getenv(var, '')
    parsed = urlparse(url)
    if parsed.scheme != 'https' and not (parsed.scheme == 'http' and parsed.hostname in ('localhost', '127.0.0.1')):
        raise HTTPException(503, f'{var} must be HTTPS or local HTTP')
    return url


@router.post('/sessions', status_code=201)
def create_session(body: StripeTestCart,
                   idempotency_key: str = Header(min_length=8, max_length=128, alias='Idempotency-Key'),
                   db: Session = Depends(get_db),
                   user: User = Depends(current_user)):
    if user.role != 'user':
        raise HTTPException(403, 'Only customers can check out')
    key = _require_test_key()
    ids = [i.product_id for i in body.items]
    if len(ids) != len(set(ids)):
        raise HTTPException(422, 'Duplicate product IDs')
    normalized = sorted(({'product_id': i.product_id, 'quantity': i.quantity} for i in body.items), key=lambda x: x['product_id'])
    fingerprint = hashlib.sha256(json.dumps(normalized, sort_keys=True).encode()).hexdigest()
    previous = db.scalar(select(StripeTestAttempt).where(
        StripeTestAttempt.user_id == user.id, StripeTestAttempt.idempotency_key == idempotency_key))
    if previous:
        if previous.fingerprint != fingerprint:
            raise HTTPException(409, 'Idempotency key reused for different cart')
        return {'session_id': previous.session_id, 'checkout_url': previous.checkout_url, 'replayed': True,
                'notice': 'Test payment only; fulfilment not enabled'}
    items = []
    total_minor = 0
    for i in normalized:
        p = db.get(Product, i['product_id'])
        if p is None or not p.is_active:
            raise HTTPException(404, 'Product unavailable')
        if p.stock < i['quantity']:
            raise HTTPException(409, 'Insufficient stock')
        cents = int((Decimal(str(p.price)) * 100).quantize(Decimal('1'), rounding=ROUND_HALF_UP))
        if cents < 50:
            raise HTTPException(422, 'Item below Stripe minimum demonstration price')
        total_minor += cents * i['quantity']
        items.append({'price_data': {'currency': 'sgd', 'product_data': {'name': p.name}, 'unit_amount': cents},
                      'quantity': i['quantity']})
    stripe = _stripe()
    stripe.api_key = key
    try:
        session = stripe.checkout.Session.create(
            mode='payment', payment_method_types=['card'], line_items=items,
            success_url=_safe_redirect('STRIPE_SUCCESS_URL'),
            cancel_url=_safe_redirect('STRIPE_CANCEL_URL'),
            metadata={'mandai_user_id': str(user.id), 'cart_fingerprint': fingerprint},
            idempotency_key=f'mandai-test-{user.id}-{idempotency_key}')
    except Exception as exc:
        raise HTTPException(502, 'Stripe test session could not be created') from exc
    attempt = StripeTestAttempt(user_id=user.id, idempotency_key=idempotency_key,
        fingerprint=fingerprint, session_id=session.id, checkout_url=session.url,
        status='pending', amount_minor=total_minor)
    db.add(attempt)
    try:
        db.commit()
    except Exception:
        db.rollback()
        # A second same-key caller may have committed; still no order/stock mutation.
        existing = db.scalar(select(StripeTestAttempt).where(
            StripeTestAttempt.user_id == user.id, StripeTestAttempt.idempotency_key == idempotency_key))
        if existing and existing.fingerprint == fingerprint:
            return {'session_id': existing.session_id, 'checkout_url': existing.checkout_url, 'replayed': True,
                    'notice': 'Test payment only; fulfilment not enabled'}
        raise HTTPException(409, 'Checkout session conflict')
    return {'session_id': session.id, 'checkout_url': session.url, 'replayed': False,
            'notice': 'Test payment only; fulfilment not enabled'}


@router.post('/webhook')
async def stripe_webhook(request: Request, db: Session = Depends(get_db)):
    _require_test_key()
    secret = os.getenv('STRIPE_WEBHOOK_SECRET', '')
    if not secret.startswith('whsec_'):
        raise HTTPException(503, 'Stripe webhook secret not configured')
    signature = request.headers.get('stripe-signature', '')
    payload = await request.body()
    try:
        event = _stripe().Webhook.construct_event(payload, signature, secret)
    except Exception as exc:
        raise HTTPException(400, 'Invalid Stripe signature or payload') from exc
    if event.get('livemode') is not False:
        raise HTTPException(400, 'Live events not accepted')
    event_id = event['id']
    if db.scalar(select(StripeWebhookEvent).where(StripeWebhookEvent.event_id == event_id)):
        return {'received': True, 'duplicate': True}
    event_type = event['type']
    obj = event['data']['object']
    if event_type in ('checkout.session.completed', 'checkout.session.async_payment_succeeded',
                      'checkout.session.async_payment_failed', 'checkout.session.expired'):
        attempt = db.scalar(select(StripeTestAttempt).where(StripeTestAttempt.session_id == obj.get('id')))
        if attempt:
            if event_type in ('checkout.session.completed', 'checkout.session.async_payment_succeeded'):
                if obj.get('payment_status') == 'paid' and obj.get('currency') == 'sgd' and obj.get('amount_total') == attempt.amount_minor:
                    attempt.status = 'paid_test_only'
                else:
                    attempt.status = 'review_required'
            else:
                attempt.status = 'failed_or_expired'
    db.add(StripeWebhookEvent(event_id=event_id, event_type=event_type))
    try:
        db.commit()
    except Exception:
        db.rollback()
        if db.scalar(select(StripeWebhookEvent).where(StripeWebhookEvent.event_id == event_id)):
            return {'received': True, 'duplicate': True}
        raise HTTPException(503, 'Webhook storage failed; Stripe should retry')
    return {'received': True}
