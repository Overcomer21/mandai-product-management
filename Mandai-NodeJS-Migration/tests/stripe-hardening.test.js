import test from 'node:test';
import assert from 'node:assert/strict';
import {paymentReturnPage, validSessionId} from '../src/interfaces/payment-return.js';
import {StripeCheckoutService} from '../src/application/stripe-checkout-service.js';
import {validateCart} from '../src/domain/stripe-policy.js';

const user = {id: 7, role: 'user'};
const body = {items:[{product_id:4,quantity:1}],delivery_address:'123 Example Street Singapore'};
const sid = 'cs_test_12345678ABC';

test('payment-return is display-only and does not claim payment success',()=>{
 const page=paymentReturnPage('success',sid,'http://127.0.0.1:3000');
 assert.match(page.html,/Payment status must be verified/);
 assert.match(page.html,/mandai-merchandise:\/\/payment-return/);
 assert.match(page.html,/Return to Flutter Web/);
 assert.match(page.headers['Cache-Control'],/no-store/);
 assert.match(page.headers['Content-Security-Policy'],/nonce-/);
 assert.doesNotMatch(page.html,/approved_test|payment_status.*paid/);
});
test('payment-return rejects unknown outcomes, bad sessions and unsafe redirects',()=>{
 assert.equal(validSessionId(sid),true);
 assert.throws(()=>paymentReturnPage('paid',sid),{status:404});
 assert.throws(()=>paymentReturnPage('success','<script>'),{status:400});
 assert.throws(()=>paymentReturnPage('success',sid,'https://user:pass@example.org'),{status:503});
 assert.throws(()=>paymentReturnPage('success',sid,'javascript:alert(1)'),{status:503});
});
test('payment-return preserves existing query parameters',()=>{
 const page=paymentReturnPage('cancel',sid,'http://localhost:3000/orders?source=checkout');
 assert.match(page.html,/source=checkout&amp;session_id=/);
 assert.match(page.html,/result=cancel/);
});
test('session-to-order lookup only uses owned sessions', async()=>{
 let requested;
 const service=new StripeCheckoutService({ownedBySession:async(uid,id)=>{requested={uid,id};return {id:82};}},{});
 assert.deepEqual(await service.orderForSession(user,sid),{order_id:82,invoice_number:'MND-00000082'});
 assert.deepEqual(requested,{uid:7,id:sid});
 await assert.rejects(()=>service.orderForSession(user,'cs_bad'),{status:404});
 await assert.rejects(()=>service.orderForSession({id:1,role:'admin'},sid),{status:403});
});
test('uncertain session and failed review both fail closed', async()=>{
 const repo={existing:async()=>null,reserve:async()=>({orderId:82,lineItems:[]}),markReview:async()=>{throw new Error('SQL unavailable')}};
 const gateway={create:async()=>{throw new Error('Stripe timeout')}};
 await assert.rejects(()=>new StripeCheckoutService(repo,gateway).create(user,'replay-key-123',body),{status:503});
});
test('idempotency rejects changed cart before reserving stock', async()=>{
 const prior=validateCart(body).fingerprint;
 const repo={existing:async()=>({fingerprint:prior,attempt_id:1,status:'pending'}),reserve:async()=>{throw Error('must not reserve')}};
 const change={...body,items:[{product_id:4,quantity:2}]};
 await assert.rejects(()=>new StripeCheckoutService(repo,{}).create(user,'replay-key-123',change),{status:409});
});
