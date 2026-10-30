"""Reconcile a paid TEST Checkout Session into one existing order, idempotently.

No stock reduction occurs here: stock was reserved in create_session.
"""
from fastapi import HTTPException
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session
from .models import Order, Payment
from .stripe_checkout_router import StripeCheckoutAttempt, _stripe, _minor


def read_stripe_session(attempt: StripeCheckoutAttempt):
    if not attempt.session_id or not attempt.session_id.startswith('cs_test_'):
        raise HTTPException(409, 'Checkout session is not ready for reconciliation')
    try:
        return _stripe().checkout.Session.retrieve(attempt.session_id)
    except Exception as exc:
        # A failed Stripe API call MUST NOT be interpreted as payment failure.
        raise HTTPException(503, 'Stripe status unavailable; retry status verification later') from exc


def reconcile_paid_order(db: Session, order: Order, attempt: StripeCheckoutAttempt, session):
    """Only a server-verified, matching paid Stripe session may settle an order."""
    if (session.get('livemode') is not False or session.get('id') != attempt.session_id):
        raise HTTPException(409, 'Stripe session verification failed')
    if (str(session.get('client_reference_id')) != str(order.id)
            or str((session.get('metadata') or {}).get('order_id')) != str(order.id)
            or str(session.get('currency') or '').lower() != 'sgd'
            or session.get('amount_total') != attempt.amount_minor
            or session.get('amount_total') != _minor(order.total_amount)):
        raise HTTPException(409, 'Stripe session does not match this invoice')
    if session.get('status') != 'complete' or session.get('payment_status') != 'paid':
        return 'not_paid'
    intent_id = session.get('payment_intent')
    if not isinstance(intent_id, str) or not intent_id.startswith('pi_'):
        raise HTTPException(409, 'Payment Intent missing; manual verification required')
    existing = db.scalar(select(Payment).where(Payment.order_id == order.id))
    if order.status == 'completed' and attempt.status == 'paid' and existing:
        if existing.provider_reference != intent_id or existing.status != 'approved_test':
            raise HTTPException(409, 'Recorded payment requires manual reconciliation')
        return 'already_paid'
    if existing or order.status != 'pending_payment' or attempt.status not in ('pending', 'review_required', 'creating'):
        raise HTTPException(409, 'Order is not safely settleable; manual reconciliation required')
    try:
        # Conditional update serializes concurrent webhook/reconciliation workers.
        claimed = db.execute(update(StripeCheckoutAttempt).where(
            StripeCheckoutAttempt.id == attempt.id,
            StripeCheckoutAttempt.status == attempt.status
        ).values(status='processing'))
        if claimed.rowcount != 1:
            db.rollback()
            raise HTTPException(409, 'Payment settlement in progress; refresh status')
        db.add(Payment(order_id=order.id, method='stripe_test',
                       provider_reference=intent_id, card_last4=None,
                       amount=order.total_amount, status='approved_test'))
        order.status = 'completed'
        attempt.status = 'paid'
        db.commit()
    except (IntegrityError, OperationalError) as exc:
        db.rollback()
        raise HTTPException(409, 'Payment settlement conflict; verify order status before retry') from exc
    except Exception:
        db.rollback()
        raise
    return 'settled'
