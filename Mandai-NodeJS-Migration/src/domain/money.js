import {fail} from '../shared/errors.js';
export function cents(v){const n=Number(v);if(!Number.isFinite(n)||n<0)fail(422,'Invalid monetary amount');return Math.round(n*100);}
export function amount(c){return (c/100).toFixed(2)}
export const deliveryFeeCents=490;
export function purchaseFingerprintInput(body){return {product_id:body.product_id,quantity:body.quantity};}
export function checkoutFingerprintInput(body){return {delivery_address:body.delivery_address,items:[...body.items].sort((a,b)=>a.product_id-b.product_id),payment_method:body.payment_method,simulate_decline:body.simulate_decline??false};}
