"""Authenticated customer-facing verification/resume of existing Stripe orders."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from urllib.parse import urlparse
from sqlalchemy.orm import Session
from .database import get_db
from .models import Order, Payment, User
from .security import current_user
from .stripe_checkout_router import StripeCheckoutAttempt
from .stripe_payment_settlement import read_stripe_session, reconcile_paid_order

router = APIRouter(prefix='/api/stripe-checkout/orders', tags=['Stripe payment recovery'])


def _owned_order(order_id: int, db: Session, user: User):
    if user.role != 'user':
        raise HTTPException(403, 'Customer login required')
    order = db.get(Order, order_id)
    if order is None or order.user_id != user.id:
        raise HTTPException(404, 'Order not found')
    attempt = db.scalar(select(StripeCheckoutAttempt).where(StripeCheckoutAttempt.order_id == order_id))
    if attempt is None:
        raise HTTPException(404, 'Stripe checkout attempt not found')
    return order, attempt


def _result(db, order, attempt):
    payment = db.scalar(select(Payment).where(Payment.order_id == order.id))
    return {'order_id': order.id, 'invoice_number': f'MND-{order.id:08d}',
            'order_status': order.status, 'payment_status': payment.status if payment else 'pending',
            'attempt_status': attempt.status,
            'amount': str(order.total_amount)}


@router.post('/{order_id}/reconcile')
def reconcile(order_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    order, attempt = _owned_order(order_id, db, user)
    session = read_stripe_session(attempt)
    state = reconcile_paid_order(db, order, attempt, session)
    return {**_result(db, order, attempt), 'stripe_checkout_status': session.get('status'),
            'stripe_payment_status': session.get('payment_status'), 'reconciliation': state}


@router.get('/{order_id}/resume')
def resume(order_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    order, attempt = _owned_order(order_id, db, user)
    session = read_stripe_session(attempt)
    # Paid sessions may need settlement, not another payment attempt.
    if session.get('payment_status') == 'paid':
        raise HTTPException(409, 'Payment already paid at Stripe; verify status instead')
    if order.status != 'pending_payment' or attempt.status != 'pending':
        raise HTTPException(409, 'Checkout cannot be resumed; verify status first')
    if session.get('status') != 'open' or session.get('payment_status') != 'unpaid':
        raise HTTPException(409, 'Checkout is not open; verify status first')
    if session.get('livemode') is not False or session.get('id') != attempt.session_id:
        raise HTTPException(409, 'Invalid Stripe session')
    # Return the existing URL, never create or charge a new session.
    url = attempt.checkout_url
    if not url or urlparse(url).scheme != 'https' or urlparse(url).hostname != 'checkout.stripe.com':
        raise HTTPException(409, 'Checkout URL not available')
    return {'order_id': order_id, 'invoice_number': f'MND-{order_id:08d}', 'checkout_url': url}
