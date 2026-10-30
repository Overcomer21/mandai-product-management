"""Untrusted browser return page and authenticated session-to-order lookup.

No fulfillment, Stripe API calls, inventory changes, or payment writes occur here.
"""
import html
import json
import os
import re
import secrets
from urllib.parse import urlparse, urlencode

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

    # A return URL is NEVER proof of payment. Verify via authenticated APIs/webhook.
    params = urlencode({'session_id': session_id, 'result': outcome})
    deeplink = 'mandai-merchandise://payment-return?' + params

    # This setting is for a separate Flutter WEB origin, not an Android deep link.
    web_base = os.getenv('STRIPE_WEB_RETURN_URL', '').strip()
    web_link = ''
    if web_base:
        parsed = urlparse(web_base)
        if parsed.scheme != 'https' and not (
            parsed.scheme == 'http' and parsed.hostname in ('localhost', '127.0.0.1')
        ):
            raise HTTPException(503, 'Invalid configured web return URL')
        joiner = '&' if parsed.query else '?'
        web_link = web_base + joiner + params

    escaped_app = html.escape(deeplink, quote=True)
    escaped_web = html.escape(web_link, quote=True)
    label = 'Checkout completed' if outcome == 'success' else 'Checkout cancelled'
    web_button = f'<p><a href="{escaped_web}">Return to Flutter Web</a></p>' if web_link else ''

    # Best-effort automatic return on Android. Browsers can block custom-scheme
    # navigation without a user gesture, so retain the clickable fallback.
    nonce = secrets.token_urlsafe(18)
    script_url = json.dumps(deeplink)
    html_body = f'''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mandai payment return</title></head>
<body style="font:16px system-ui;max-width:34rem;margin:8vh auto;padding:1.5rem">
<h1>{html.escape(label)}</h1>
<p>Returning to the Mandai app. Payment status will be verified securely in the app.</p>
<p><a href="{escaped_app}">Open Mandai Merchandise app</a></p>
{web_button}
<p>If the app does not open automatically, tap the link above, or return to Orders and select Verify / Resume Stripe.</p>
<script nonce="{nonce}">
(function () {{
  // Chrome/Android may require a user gesture; manual link remains available.
  if (/Android/i.test(navigator.userAgent)) {{
    window.location.assign({script_url});
  }}
}})();
</script>
</body></html>'''
    return HTMLResponse(html_body, headers={
        'Cache-Control': 'no-store',
        'Content-Security-Policy': (
            "default-src 'none'; style-src 'unsafe-inline'; "
            f"script-src 'nonce-{nonce}'; base-uri 'none'; form-action 'none'"
        ),
        'Referrer-Policy': 'no-referrer',
        'X-Content-Type-Options': 'nosniff',
    })


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
