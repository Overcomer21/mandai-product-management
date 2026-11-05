import {randomBytes} from 'node:crypto';
import {fail} from '../shared/errors.js';

export const validSessionId=id=>typeof id==='string'&&/^cs_test_[A-Za-z0-9_]{8,255}$/.test(id);
const escapeHtml=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function paymentReturnPage(outcome,sessionId,webBase=process.env.STRIPE_WEB_RETURN_URL||''){
 if(!['success','cancel'].includes(outcome))fail(404,'Unknown return endpoint');
 if(!validSessionId(sessionId))fail(400,'Invalid checkout session reference');
 const query=new URLSearchParams({session_id:sessionId,result:outcome}).toString();
 const deeplink=`mandai-merchandise://payment-return?${query}`;
 let webUrl=null;
 if(webBase){
  let parsed;try{parsed=new URL(webBase);}catch{fail(503,'Invalid configured web return URL');}
  if(parsed.protocol!=='https:'&&!(parsed.protocol==='http:'&&['localhost','127.0.0.1'].includes(parsed.hostname)))fail(503,'Invalid configured web return URL');
  if(parsed.username||parsed.password)fail(503,'Invalid configured web return URL');
  parsed.searchParams.set('session_id',sessionId);parsed.searchParams.set('result',outcome);webUrl=parsed.toString();
 }
 const nonce=randomBytes(18).toString('base64url');
 const label=outcome==='success'?'Checkout completed':'Checkout cancelled';
 const app=escapeHtml(deeplink);
 const web=webUrl?`<p><a href="${escapeHtml(webUrl)}">Return to Flutter Web</a></p>`:'';
 const scriptUrl=JSON.stringify(deeplink).replace(/</g,'\\u003c');
 const html=`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Mandai payment return</title></head><body style="font:16px system-ui;max-width:34rem;margin:8vh auto;padding:1.5rem"><h1>${escapeHtml(label)}</h1><p>Payment status must be verified in Mandai. This page is not payment confirmation.</p><p><a href="${app}">Open Mandai Merchandise app</a></p>${web}<p>If the app does not open, return to Orders and select Verify / Resume Stripe.</p><script nonce="${nonce}">(function(){if(/Android/i.test(navigator.userAgent)){window.location.assign(${scriptUrl});}})();</script></body></html>`;
 return {html,headers:{'Cache-Control':'no-store','Content-Security-Policy':`default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; base-uri 'none'; form-action 'none'`,'Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'}};
}
