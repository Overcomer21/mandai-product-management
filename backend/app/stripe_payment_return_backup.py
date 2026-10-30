"""Untrusted browser return page and authenticated session-to-order lookup.

No fulfillment, Stripe API calls, inventory changes, or payment writes occur here.
"""
import html
import os
import re
from urllib.parse import quote, urlparse, urlencode
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.orm import Session
from .database import get_db
from .models import Order, User
from .security import current_user
from .stripe_checkout_router import StripeCheckoutAttempt

router = APIRouter(tags=['Stripe payment return'])
_SESSION_RE = re.compile(r'^cs_test_[A-Za-z0-9_]{8,255}$')

@router.get('/api/payment-return/{outcome}', response_class=HTMLResponse, include_in_schema=True)
def browser_return(outcome: str, session_id: str = ''):
    if outcome not in ('success', 'cancel'):
        raise HTTPException(404, 'Unknown return endpoint')
    if not _SESSION_RE.fullmatch(session_id):
        raise HTTPException(400, 'Invalid checkout session reference')
    # A return URL is NEVER proof of payment. All sensitive operations are in /reconcile.
    params = urlencode({'session_id': session_id, 'result': outcome})
    deeplink = 'mandai-merchandise://payment-return?' + params
    web_base = os.getenv('STRIPE_WEB_RETURN_URL', '').strip()
    web_link = ''
    if web_base:
        parsed = urlparse(web_base)
        if parsed.scheme != 'https' and not (parsed.scheme == 'http' and parsed.hostname in ('localhost','127.0.0.1')):
            raise HTTPException(503, 'Invalid configured web return URL')
        joiner = '&' if parsed.query else '?'
        web_link = web_base + joiner + params
    escaped_app = html.escape(deeplink, quote=True)
    escaped_web = html.escape(web_link, quote=True)
    label = 'Checkout completed' if outcome == 'success' else 'Checkout cancelled'
    web_button = f'<p><a href="{escaped_web}">Return to Flutter Web</a></p>' if web_link else ''
    # Do not auto launch on page load: browser restrictions and accidental opening on desktops.
    # Explicit tap launches custom URI, or user can use Web link / manual Orders check.
    return HTMLResponse(f'''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Mandai payment return</title></head>
<body style="font:16px system-ui;max-width:34rem;margin:8vh auto;padding:1.5rem">
<h1>{html.escape(label)}</h1><p>Return to the app to verify payment securely. This page is not payment confirmation.</p>
<p><a href="{escaped_app}">Return to Mandai Merchandise (Android / Windows)</a></p>
{web_button}<p>If the app does not open, switch back manually and select Verify / Resume Stripe in Orders.</p>
</body></html>''', headers={'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'", 'Referrer-Policy': 'no-referrer'})

@router.get('/api/stripe-checkout/return/session/{session_id}')
def owned_order_for_session(session_id: str, db: Session = Depends(get_db), user: User = Depends(current_user)):
    if user.role != 'user' or not _SESSION_RE.fullmatch(session_id):
        raise HTTPException(404, 'Checkout session not found')
    attempt = db.scalar(select(StripeCheckoutAttempt).where(
        StripeCheckoutAttempt.session_id == session_id,
        StripeCheckoutAttempt.user_id == user.id))
    if attempt is None:
        raise HTTPException(404, 'Checkout session not found')
    order = db.get(Order, attempt.order_id)
    if order is None or order.user_id != user.id:
        raise HTTPException(404, 'Checkout session not found')
    return {'order_id': order.id, 'invoice_number': f'MND-{order.id:08d}'}
