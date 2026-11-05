import {createHash} from 'node:crypto';
import {pythonJson} from './fingerprint.js';
import {fail,requireInteger} from '../shared/errors.js';
export function validateCart(body){
 if(!body||!Array.isArray(body.items)||body.items.length<1||body.items.length>30||typeof body.delivery_address!=='string'||body.delivery_address.length<10||body.delivery_address.length>500)fail(422,'Invalid checkout');
 const items=body.items.map(x=>({product_id:requireInteger(x.product_id,{name:'product_id',min:1}),quantity:requireInteger(x.quantity,{name:'quantity',min:1,max:100})})).sort((a,b)=>a.product_id-b.product_id);
 if(new Set(items.map(x=>x.product_id)).size!==items.length)fail(422,'Duplicate product IDs');
 const address=body.delivery_address.trim();
 return {items,address,fingerprint:createHash('sha256').update(pythonJson({items,address,method:'stripe_test'})).digest('hex')};
}
export function moneyMinor(n){const value=Number(n);if(!Number.isFinite(value)||value<0)fail(409,'Invalid amount');return Math.round((value+Number.EPSILON)*100);}
export function checkSession(s,order,attempt,{expiration=false,settlement=false}={}){
 const good=s?.livemode===false&&s.id===attempt.session_id&&String(s.client_reference_id)===String(order.id)&&String(s.metadata?.order_id)===String(order.id)&&String(s.currency).toLowerCase()==='sgd'&&s.amount_total===attempt.amount_minor&&s.amount_total===moneyMinor(order.total);
 if(!good)fail(409,'Stripe session does not match this invoice');
 if(expiration&&(s.status!=='expired'||s.payment_status!=='unpaid'))fail(409,'Stripe session is not verified expired and unpaid');
 if(settlement&&(s.status!=='complete'||s.payment_status!=='paid'))return false;
 return true;
}
export function requireStripeConfig(env){
 if(!env.STRIPE_SECRET_KEY?.startsWith('sk_test_'))fail(503,'Stripe test key is missing or invalid');
 for(const name of ['STRIPE_SUCCESS_URL','STRIPE_CANCEL_URL']){
  let u;try{u=new URL(env[name]);}catch{fail(503,`${name} is invalid`)}
  if(u.protocol!=='https:'&&!(u.protocol==='http:'&&['localhost','127.0.0.1'].includes(u.hostname)))fail(503,`${name} requires HTTPS or localhost`);
 }
 const minutes=Number(env.STRIPE_CHECKOUT_EXPIRY_MINUTES||30);
 if(!Number.isSafeInteger(minutes)||minutes<30||minutes>1440)fail(503,'Invalid Stripe checkout expiry');
 return minutes;
}
export function stripeResponse(a){return {order_id:a.order_id,invoice_number:`MND-${String(a.order_id).padStart(8,'0')}`,status:a.status,session_id:a.session_id??null,checkout_url:a.checkout_url??null};}
