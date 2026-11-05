import {fail} from '../shared/errors.js';
import {validateCart,stripeResponse,checkSession} from '../domain/stripe-policy.js';
export class StripeCheckoutService{
 constructor(repository,gateway,cache=null){this.repo=repository;this.gateway=gateway;this.cache=cache;}
 async invalidateCatalog(){await this.cache?.invalidate();}
 customer(user){if(user?.role!=='user')fail(403,'Customer login required');}
 async create(user,key,body){
  this.customer(user);if(typeof key!=='string'||key.length<8||key.length>128)fail(422,'Invalid Idempotency-Key');
  const {items,address,fingerprint}=validateCart(body);
  const prior=await this.repo.existing(user.id,key);
  if(prior){if(prior.fingerprint!==fingerprint)fail(409,'Idempotency key used for different checkout');if(!prior.attempt_id)fail(409,'Idempotency key belongs to another payment method');if(prior.status==='creating')fail(409,'Payment session is being prepared; retry with same key');return stripeResponse(prior)}
  let reservation;
  try{reservation=await this.repo.reserve(user.id,key,fingerprint,items,address)}catch(e){
   // Another request may have inserted the same idempotency key.
   if([2601,2627].includes(e.number)||[2601,2627].includes(e.originalError?.info?.number))fail(409,'Concurrent checkout conflict; retry with same key');throw e;
  }
  // Reservation has committed and changed Products.Stock.
  await this.invalidateCatalog();
  let session;
  try{session=await this.gateway.create({userId:user.id,key,orderId:reservation.orderId,lineItems:reservation.lineItems})}
  catch{try{await this.repo.markReview(reservation.orderId);}catch{fail(503,'Unable to mark uncertain Stripe session; manual verification required. Do not pay again');}fail(502,'Stripe session uncertain; contact support before retrying or repaying')}
  try{await this.repo.saveSession(reservation.orderId,session)}catch{fail(503,'Stripe session needs reconciliation; do not pay again')}
  return stripeResponse({order_id:reservation.orderId,status:'pending',session_id:session.id,checkout_url:session.url});
 }
 async status(user,id){this.customer(user);const x=await this.repo.status(user.id,id);return {...stripeResponse(x.attempt),order_status:x.order.status,payment_status:x.payment_status,total_amount:Number(x.order.total).toFixed(2)};}
 async cancel(user,id){this.customer(user);const x=await this.repo.owned(user.id,id);if(x.order.status==='expired'&&x.attempt.status==='expired')return {order_id:id,status:'expired'};
  if(x.order.status!=='pending_payment'||!['pending','review_required'].includes(x.attempt.status)||!x.attempt.session_id)fail(409,'Order cannot be cancelled in its current state');
  let session;try{session=await this.gateway.retrieve(x.attempt.session_id);if(session.status==='open')session=await this.gateway.expire(x.attempt.session_id);}catch(e){if(e.status)throw e;fail(503,'Unable to confirm cancellation with Stripe; retry later')}
  if(session.status==='complete')fail(409,'Payment completed or is being finalized; cannot cancel');
  const state=await this.repo.release(id,session);
  if(state==='expired')await this.invalidateCatalog();
  return {order_id:id,status:'expired',reconciliation:state};
 }
 async reconcile(user,id){this.customer(user);const x=await this.repo.owned(user.id,id);if(!x.attempt.session_id)fail(409,'Stripe session reference missing; manual verification required. Do not pay again.');
  let session;try{session=await this.gateway.retrieve(x.attempt.session_id)}catch(e){if(e.status)throw e;fail(503,'Stripe status unavailable; retry later')}
  let result;
  if(session.status==='expired'&&session.payment_status==='unpaid'){
   result=await this.repo.release(id,session);
   if(result==='expired')await this.invalidateCatalog();
  }else result=await this.repo.settle(id,session);
  const state=await this.repo.status(user.id,id);
  return {order_id:id,invoice_number:`MND-${String(id).padStart(8,'0')}`,order_status:state.order.status,payment_status:state.payment_status,attempt_status:state.attempt.status,amount:Number(state.order.total).toFixed(2),stripe_checkout_status:session.status,stripe_payment_status:session.payment_status,reconciliation:result};
 }
 async resume(user,id){this.customer(user);const x=await this.repo.owned(user.id,id);let session;try{session=await this.gateway.retrieve(x.attempt.session_id)}catch(e){if(e.status)throw e;fail(503,'Stripe status unavailable')}
  checkSession(session,x.order,x.attempt);
  if(session.payment_status==='paid')fail(409,'Payment already paid at Stripe; verify status instead');
  if(x.order.status!=='pending_payment'||x.attempt.status!=='pending'||session.status!=='open'||session.payment_status!=='unpaid')fail(409,'Checkout cannot be resumed; verify status first');
  let u;try{u=new URL(x.attempt.checkout_url)}catch{fail(409,'Checkout URL not available')}
  if(u.protocol!=='https:'||u.hostname!=='checkout.stripe.com')fail(409,'Checkout URL not available');
  return {order_id:id,invoice_number:`MND-${String(id).padStart(8,'0')}`,checkout_url:u.toString()};
 }
 async orderForSession(user,sessionId){this.customer(user);if(!/^cs_test_[A-Za-z0-9_]{8,255}$/.test(sessionId))fail(404,'Checkout session not found');const order=await this.repo.ownedBySession(user.id,sessionId);return {order_id:order.id,invoice_number:`MND-${String(order.id).padStart(8,'0')}`};}
 async webhook(payload,signature){
  const event=this.gateway.verify(payload,signature);
  if(event.livemode!==false)fail(400,'Live events rejected');
  const result=await this.repo.processEvent(event);
  // Event processing commits before returning. Invalidate on release events;
  // if an unrelated event was recorded, extra invalidation is harmless.
  if(result?.received&&!result?.duplicate&&
     ['checkout.session.expired','checkout.session.async_payment_failed'].includes(event.type))
   await this.invalidateCatalog();
  return result;
 }
}
