"""Isolated STRIPE TEST MODE order/payment pipeline; existing /api/checkout unchanged."""
import hashlib
import json
import os
import uuid
from decimal import Decimal, ROUND_HALF_UP
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, Header, Request
from pydantic import BaseModel, Field
from sqlalchemy import select, update, UniqueConstraint, ForeignKey, Integer, String, DateTime, func
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Mapped, mapped_column, Session

from .database import Base, get_db
from .models import User, Product, Order, OrderItem, Payment
from .security import current_user

router = APIRouter(prefix='/api/stripe-checkout', tags=['Stripe sandbox checkout'])
FEE = Decimal('4.90')


class StripeCheckoutAttempt(Base):
    __tablename__ = 'StripeCheckoutAttempts'
    id: Mapped[int] = mapped_column('Id', Integer, primary_key=True)
    order_id: Mapped[int] = mapped_column('OrderId', ForeignKey('Orders.Id'), unique=True, nullable=False)
    user_id: Mapped[int] = mapped_column('UserId', ForeignKey('Users.Id'), nullable=False)
    session_id: Mapped[str | None] = mapped_column('SessionId', String(255), unique=True)
    checkout_url: Mapped[str | None] = mapped_column('CheckoutUrl', String(2048))
    status: Mapped[str] = mapped_column('Status', String(30), nullable=False)
    amount_minor: Mapped[int] = mapped_column('AmountMinor', Integer, nullable=False)
    created_at = mapped_column('CreatedAt', DateTime(timezone=True), server_default=func.current_timestamp())


class StripeCheckoutEvent(Base):
    __tablename__ = 'StripeCheckoutEvents'
    id: Mapped[int] = mapped_column('Id', Integer, primary_key=True)
    event_id: Mapped[str] = mapped_column('EventId', String(255), unique=True, nullable=False)
    event_type: Mapped[str] = mapped_column('EventType', String(100), nullable=False)
    created_at = mapped_column('CreatedAt', DateTime(timezone=True), server_default=func.current_timestamp())


class Item(BaseModel):
    product_id: int = Field(gt=0)
    quantity: int = Field(gt=0, le=100)


class RequestCart(BaseModel):
    items: list[Item] = Field(min_length=1, max_length=30)
    delivery_address: str = Field(min_length=10, max_length=500)


def _stripe():
    key = os.getenv('STRIPE_SECRET_KEY', '')
    if not key.startswith('sk_test_'):
        raise HTTPException(503, 'Stripe test key is missing or invalid')
    try:
        import stripe
    except ImportError as exc:
        raise HTTPException(503, 'Install stripe Python SDK') from exc
    stripe.api_key = key
    return stripe


def _redirect(name):
    url = os.getenv(name, '')
    parsed = urlparse(url)
    if parsed.scheme != 'https' and not (parsed.scheme == 'http' and parsed.hostname in ('localhost', '127.0.0.1')):
        raise HTTPException(503, f'{name} requires HTTPS or localhost')
    return url


def _minor(amount):
    return int((amount * 100).quantize(Decimal('1'), rounding=ROUND_HALF_UP))


def _fingerprint(items, address):
    return hashlib.sha256(json.dumps({'items': items, 'address': address, 'method': 'stripe_test'}, sort_keys=True).encode()).hexdigest()


def _attempt_response(attempt):
    return {'order_id': attempt.order_id, 'invoice_number': f'MND-{attempt.order_id:08d}',
            'status': attempt.status, 'session_id': attempt.session_id, 'checkout_url': attempt.checkout_url}


@router.post('/sessions', status_code=201)
def create_session(body: RequestCart, idempotency_key: str = Header(min_length=8, max_length=128, alias='Idempotency-Key'),
                   db: Session = Depends(get_db), user: User = Depends(current_user)):
    if user.role != 'user':
        raise HTTPException(403, 'Customer login required')
    stripe = _stripe()
    success_url = _redirect('STRIPE_SUCCESS_URL')
    cancel_url = _redirect('STRIPE_CANCEL_URL')
    items = sorted([i.model_dump() for i in body.items], key=lambda x: x['product_id'])
    if len({i['product_id'] for i in items}) != len(items):
        raise HTTPException(422, 'Duplicate product IDs')
    fingerprint = _fingerprint(items, body.delivery_address.strip())
    existing = db.scalar(select(Order).where(Order.user_id == user.id, Order.idempotency_key == idempotency_key))
    if existing:
        if existing.request_fingerprint != fingerprint:
            raise HTTPException(409, 'Idempotency key used for different checkout')
        attempt = db.scalar(select(StripeCheckoutAttempt).where(StripeCheckoutAttempt.order_id == existing.id))
        if not attempt:
            raise HTTPException(409, 'Idempotency key belongs to another payment method')
        if attempt.status == 'creating':
            raise HTTPException(409, 'Payment session is being prepared; retry with same key')
        return _attempt_response(attempt)

    subtotal = Decimal('0.00')
    line_items = []
    try:
        # Reserve inventory atomically before external payment. Order remains pending.
        order = Order(user_id=user.id, idempotency_key=idempotency_key, request_fingerprint=fingerprint,
                      total_amount=Decimal('0.00'), status='pending_payment', delivery_address=body.delivery_address.strip())
        db.add(order)
        db.flush()
        for i in items:
            p = db.get(Product, i['product_id'])
            if p is None or not p.is_active:
                raise HTTPException(404, 'Product unavailable')
            stock = db.execute(update(Product).where(Product.id == p.id, Product.is_active == True,
                Product.stock >= i['quantity']).values(stock=Product.stock - i['quantity']))
            if stock.rowcount != 1:
                raise HTTPException(409, f'Insufficient stock for product {p.id}')
            subtotal += p.price * i['quantity']
            db.add(OrderItem(order_id=order.id, product_id=p.id, quantity=i['quantity'], unit_price=p.price))
            line_items.append({'price_data': {'currency': 'sgd', 'product_data': {'name': p.name},
                                              'unit_amount': _minor(p.price)}, 'quantity': i['quantity']})
        order.total_amount = subtotal + FEE
        line_items.append({'price_data': {'currency': 'sgd', 'product_data': {'name': 'Delivery'},
                                          'unit_amount': _minor(FEE)}, 'quantity': 1})
        db.add(StripeCheckoutAttempt(order_id=order.id, user_id=user.id, status='creating', amount_minor=_minor(order.total_amount)))
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except (IntegrityError, OperationalError):
        db.rollback()
        raise HTTPException(409, 'Concurrent checkout conflict; retry using the same key')

    try:
        # Stable idempotency key prevents duplicate Stripe sessions on network retries.
        session = stripe.checkout.Session.create(mode='payment', payment_method_types=['card'], line_items=line_items,
            success_url=success_url, cancel_url=cancel_url,
            client_reference_id=str(order.id), metadata={'order_id': str(order.id), 'invoice_number': f'MND-{order.id:08d}'},
            payment_intent_data={'metadata': {'order_id': str(order.id)}},
            idempotency_key=f'mandai-checkout-{user.id}-{idempotency_key}')
    except Exception as exc:
        # Do not release reservation blindly; an unknown network outcome may have created a Stripe session.
        # Keep pending for recovery/reconciliation. No charge is claimed.
        attempt = db.scalar(select(StripeCheckoutAttempt).where(StripeCheckoutAttempt.order_id == order.id))
        if attempt:
            attempt.status = 'review_required'
            db.commit()
        raise HTTPException(502, 'Stripe session uncertain; contact support before retrying or repaying') from exc

    attempt = db.scalar(select(StripeCheckoutAttempt).where(StripeCheckoutAttempt.order_id == order.id))
    attempt.session_id = session.id
    attempt.checkout_url = session.url
    attempt.status = 'pending'
    db.commit()
    return _attempt_response(attempt)


@router.get('/orders/{order_id}')
def get_status(order_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    order = db.get(Order, order_id)
    if not order or order.user_id != user.id or user.role != 'user':
        raise HTTPException(404, 'Order not found')
    attempt = db.scalar(select(StripeCheckoutAttempt).where(StripeCheckoutAttempt.order_id == order_id))
    if not attempt:
        raise HTTPException(404, 'Not a Stripe checkout order')
    payment = db.scalar(select(Payment).where(Payment.order_id == order_id))
    return {**_attempt_response(attempt), 'order_status': order.status,
            'payment_status': payment.status if payment else 'pending', 'total_amount': str(order.total_amount)}


def _release_reserved_stock(db, order):
    for item in order.items:
        db.execute(update(Product).where(Product.id == item.product_id)
                   .values(stock=Product.stock + item.quantity))


@router.post('/webhook')
async def webhook(request: Request, db: Session = Depends(get_db)):
    stripe = _stripe()
    secret = os.getenv('STRIPE_WEBHOOK_SECRET', '')
    if not secret.startswith('whsec_'):
        raise HTTPException(503, 'Stripe webhook secret is not configured')
    try:
        event = stripe.Webhook.construct_event(await request.body(), request.headers.get('stripe-signature', ''), secret)
    except Exception as exc:
        raise HTTPException(400, 'Invalid signature') from exc
    if event.get('livemode') is not False:
        raise HTTPException(400, 'Live events rejected')
    event_id = event['id']
    if db.scalar(select(StripeCheckoutEvent).where(StripeCheckoutEvent.event_id == event_id)):
        return {'received': True, 'duplicate': True}
    kind = event['type']
    obj = event['data']['object']
    known = {'checkout.session.completed', 'checkout.session.async_payment_succeeded',
             'checkout.session.async_payment_failed', 'checkout.session.expired'}
    if kind in known:
        attempt = db.scalar(select(StripeCheckoutAttempt).where(StripeCheckoutAttempt.session_id == obj.get('id')))
        if attempt:
            order = db.get(Order, attempt.order_id)
            if kind in ('checkout.session.completed', 'checkout.session.async_payment_succeeded'):
                if (obj.get('payment_status') == 'paid' and obj.get('currency') == 'sgd'
                    and obj.get('amount_total') == attempt.amount_minor
                    and str(obj.get('client_reference_id')) == str(order.id)
                    and str((obj.get('metadata') or {}).get('order_id')) == str(order.id)):
                    if attempt.status == 'pending' and order.status == 'pending_payment':
                        # Conditional write serializes competing callbacks across SQL Server workers.
                        claim = db.execute(update(StripeCheckoutAttempt).where(
                            StripeCheckoutAttempt.id == attempt.id, StripeCheckoutAttempt.status == 'pending'
                        ).values(status='processing'))
                        if claim.rowcount != 1:
                            db.rollback()
                            raise HTTPException(503, 'Concurrent webhook; retry')
                        intent_id = obj.get('payment_intent')
                        if not isinstance(intent_id, str) or not intent_id.startswith('pi_'):
                            attempt.status = 'review_required'
                        else:
                            db.add(Payment(order_id=order.id, method='stripe_test', provider_reference=intent_id,
                                           card_last4=None, amount=order.total_amount, status='approved_test'))
                            order.status = 'completed'
                            attempt.status = 'paid'
                    elif attempt.status != 'paid':
                        # Never silently fulfil a late payment after reservation release.
                        attempt.status = 'review_required'
                else:
                    attempt.status = 'review_required'
            elif kind in ('checkout.session.async_payment_failed', 'checkout.session.expired'):
                if attempt.status == 'pending' and order.status == 'pending_payment':
                    claim = db.execute(update(StripeCheckoutAttempt).where(
                        StripeCheckoutAttempt.id == attempt.id, StripeCheckoutAttempt.status == 'pending'
                    ).values(status='processing'))
                    if claim.rowcount != 1:
                        db.rollback()
                        raise HTTPException(503, 'Concurrent webhook; retry')
                    _release_reserved_stock(db, order)
                    order.status = 'payment_failed' if kind.endswith('failed') else 'expired'
                    attempt.status = 'failed' if kind.endswith('failed') else 'expired'
    db.add(StripeCheckoutEvent(event_id=event_id, event_type=kind))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if db.scalar(select(StripeCheckoutEvent).where(StripeCheckoutEvent.event_id == event_id)):
            return {'received': True, 'duplicate': True}
        raise HTTPException(503, 'Webhook transaction conflict; retry')
    except Exception:
        db.rollback()
        raise HTTPException(503, 'Webhook processing failed; retry')
    return {'received': True}
