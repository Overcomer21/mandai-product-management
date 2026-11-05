import Stripe from 'stripe';
import {fail} from '../shared/errors.js';
import {requireStripeConfig} from '../domain/stripe-policy.js';
export class StripeGateway{
 constructor(env=process.env){this.env=env;this.client=null;}
 get sdk(){requireStripeConfig(this.env);return this.client??=new Stripe(this.env.STRIPE_SECRET_KEY);}
 async create({userId,key,orderId,lineItems}){
  const minutes=requireStripeConfig(this.env);
  return this.sdk.checkout.sessions.create({mode:'payment',payment_method_types:['card'],line_items:lineItems,success_url:this.env.STRIPE_SUCCESS_URL,cancel_url:this.env.STRIPE_CANCEL_URL,expires_at:Math.floor(Date.now()/1000)+minutes*60,client_reference_id:String(orderId),metadata:{order_id:String(orderId),invoice_number:`MND-${String(orderId).padStart(8,'0')}`},payment_intent_data:{metadata:{order_id:String(orderId)}}},{idempotencyKey:`mandai-checkout-${userId}-${key}`});
 }
 retrieve(id){if(!id?.startsWith('cs_test_'))fail(409,'Checkout session is not ready for reconciliation');return this.sdk.checkout.sessions.retrieve(id);}
 expire(id){return this.sdk.checkout.sessions.expire(id);}
 verify(payload,signature){
  if(!this.env.STRIPE_WEBHOOK_SECRET?.startsWith('whsec_'))fail(503,'Stripe webhook secret not configured');
  try{return this.sdk.webhooks.constructEvent(payload,signature||'',this.env.STRIPE_WEBHOOK_SECRET)}catch{fail(400,'Invalid signature')}
 }
}
