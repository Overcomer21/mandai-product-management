import test from 'node:test';
import assert from 'node:assert/strict';
import {validateCart,checkSession,requireStripeConfig} from '../src/domain/stripe-policy.js';
import {StripeCheckoutService} from '../src/application/stripe-checkout-service.js';

const user={id:7,role:'user'};
const body={items:[{product_id:11,quantity:1},{product_id:4,quantity:2}],delivery_address:'123 Example Street Singapore'};
const session={id:'cs_test_abcdefghij',livemode:false,status:'expired',payment_status:'unpaid',currency:'sgd',amount_total:1490,client_reference_id:'22',metadata:{order_id:'22'}};
const order={id:22,total:'14.90'};
const attempt={session_id:session.id,amount_minor:1490};

test('Stripe fingerprint sorted and stable across cart order',()=>{
 const a=validateCart(body),b=validateCart({...body,items:[...body.items].reverse()});
 assert.deepEqual(a.items.map(i=>i.product_id),[4,11]);assert.equal(a.fingerprint,b.fingerprint);
});
test('duplicate cart products and invalid address rejected before DB',()=>{
 assert.throws(()=>validateCart({...body,items:[body.items[0],body.items[0]]}),{status:422});
 assert.throws(()=>validateCart({...body,delivery_address:'x'}),{status:422});
});
test('strict expired and unpaid verification',()=>{
 assert.equal(checkSession(session,order,attempt,{expiration:true}),true);
 assert.throws(()=>checkSession({...session,payment_status:'paid'},order,attempt,{expiration:true}),{status:409});
 assert.throws(()=>checkSession({...session,amount_total:1400},order,attempt,{expiration:true}),{status:409});
 assert.throws(()=>checkSession({...session,metadata:{order_id:'23'}},order,attempt,{expiration:true}),{status:409});
 assert.throws(()=>checkSession({...session,livemode:true},order,attempt,{expiration:true}),{status:409});
});
test('Stripe config rejects live secret and insecure redirects',()=>{
 const e={STRIPE_SECRET_KEY:'sk_live_fake',STRIPE_SUCCESS_URL:'https://example.org/s',STRIPE_CANCEL_URL:'https://example.org/c'};
 assert.throws(()=>requireStripeConfig(e),{status:503});
 assert.throws(()=>requireStripeConfig({...e,STRIPE_SECRET_KEY:'sk_test_fake',STRIPE_SUCCESS_URL:'http://example.org/s'}),{status:503});
 assert.equal(requireStripeConfig({...e,STRIPE_SECRET_KEY:'sk_test_fake'}),30);
});
test('idempotent session replay does not reserve twice',async()=>{
 let reservations=0;
 const fp=validateCart(body).fingerprint;
 const r={existing:async()=>({fingerprint:fp,attempt_id:8,order_id:22,status:'pending',session_id:session.id,checkout_url:'https://checkout.stripe.com/test'}) ,reserve:async()=>{reservations++;throw new Error('unexpected reserve')}};
 const s=new StripeCheckoutService(r,{});
 const x=await s.create(user,'example-key-001',body);
 assert.equal(x.order_id,22);assert.equal(reservations,0);
});
test('uncertain Stripe API result preserves inventory reservation and marks review',async()=>{
 let calls=0;
 const r={existing:async()=>null,reserve:async()=>({orderId:22,lineItems:[]}),markReview:async()=>{calls++;}};
 const gateway={create:async()=>{throw new Error('network uncertain')}};
 const s=new StripeCheckoutService(r,gateway);
 await assert.rejects(()=>s.create(user,'example-key-001',body),{status:502});assert.equal(calls,1);
});
test('cancel refuses completed Stripe session without releasing stock',async()=>{
 let released=0;
 const r={owned:async()=>({order:{id:22,status:'pending_payment'},attempt:{status:'pending',session_id:session.id}}),release:async()=>{released++;}};
 const g={retrieve:async()=>({...session,status:'complete',payment_status:'paid'})};
 await assert.rejects(()=>new StripeCheckoutService(r,g).cancel(user,22),{status:409});assert.equal(released,0);
});
