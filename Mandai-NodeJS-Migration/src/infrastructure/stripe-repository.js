import {randomUUID} from 'node:crypto';
import {query,transaction} from './db.js';
import {fail} from '../shared/errors.js';
import {moneyMinor,checkSession} from '../domain/stripe-policy.js';
const FEE=490;
const row=async(sql,values=[],tx)=>((await query(sql,values,tx)).recordset[0]??null);
const affected=async(sql,values,tx)=>(await query(sql,values,tx)).rowsAffected[0];
async function load(orderId,tx){
 const x=await row(`SELECT o.Id AS id,o.UserId AS user_id,o.TotalAmount AS total,o.Status AS status,a.Id AS attempt_id,a.SessionId AS session_id,a.CheckoutUrl AS checkout_url,a.Status AS attempt_status,a.AmountMinor AS amount_minor FROM Orders o JOIN StripeCheckoutAttempts a ON a.OrderId=o.Id WHERE o.Id=@p0`,[orderId],tx);
 return x?{order:{id:x.id,user_id:x.user_id,total:x.total,status:x.status},attempt:{id:x.attempt_id,order_id:x.id,session_id:x.session_id,checkout_url:x.checkout_url,status:x.attempt_status,amount_minor:x.amount_minor}}:null;
}
async function outbox(tx,type,orderId,products,eventId=null){
 const payload=JSON.stringify({schema_version:1,order_id:orderId,product_ids:[...new Set(products)].sort((a,b)=>a-b),stripe_event_id:eventId});
 await query(`INSERT INTO PaymentOutbox(EventId,EventType,AggregateId,Payload) VALUES (@p0,@p1,@p2,@p3)`,[randomUUID(),type,orderId,payload],tx);
}
export class SqlStripeRepository{
 async existing(userId,key){const r=await row('SELECT Id AS id,RequestFingerprint AS fingerprint FROM Orders WHERE UserId=@p0 AND IdempotencyKey=@p1',[userId,key]);if(!r)return null;const x=await load(r.id);return {...r,...(x?.attempt??{}),order_id:r.id,attempt_id:x?.attempt?.id??null};}
 async reserve(userId,key,fp,items,address){return transaction(async tx=>{
  const inserted=await row(`INSERT INTO Orders(UserId,IdempotencyKey,RequestFingerprint,TotalAmount,Status,DeliveryAddress) OUTPUT INSERTED.Id AS id VALUES (@p0,@p1,@p2,0,'pending_payment',@p3)`,[userId,key,fp,address],tx);
  const id=inserted.id;let total=FEE;const lines=[];
  for(const item of items){
   const p=await row('SELECT Id AS id, Name AS name, Price AS price FROM Products WHERE Id=@p0 AND IsActive=1',[item.product_id],tx);
   if(!p)fail(404,'Product unavailable');
   if(await affected('UPDATE Products SET Stock=Stock-@p0 WHERE Id=@p1 AND IsActive=1 AND Stock>=@p0',[item.quantity,item.product_id],tx)!==1)fail(409,`Insufficient stock for product ${item.product_id}`);
   total+=moneyMinor(p.price)*item.quantity;
   await query('INSERT INTO OrderItems(OrderId,ProductId,Quantity,UnitPrice) VALUES (@p0,@p1,@p2,@p3)',[id,item.product_id,item.quantity,p.price],tx);
   lines.push({price_data:{currency:'sgd',product_data:{name:p.name},unit_amount:moneyMinor(p.price)},quantity:item.quantity});
  }
  if(await affected('UPDATE Orders SET TotalAmount=@p0 WHERE Id=@p1',[(total/100).toFixed(2),id],tx)!==1)fail(409,'Unable to set reserved order total');
  await query(`INSERT INTO StripeCheckoutAttempts(OrderId,UserId,Status,AmountMinor) VALUES (@p0,@p1,'creating',@p2)`,[id,userId,total],tx);
  await outbox(tx,'inventory.reserved',id,items.map(i=>i.product_id));
  lines.push({price_data:{currency:'sgd',product_data:{name:'Delivery'},unit_amount:FEE},quantity:1});
  return {orderId:id,lineItems:lines};
 });}
 async saveSession(orderId,s){return transaction(async tx=>{
  if(await affected(`UPDATE StripeCheckoutAttempts SET SessionId=@p0,CheckoutUrl=@p1,Status='pending' WHERE OrderId=@p2 AND Status='creating'`,[s.id,s.url,orderId],tx)!==1)fail(409,'Checkout attempt not in creating state');
 });}
 async markReview(orderId){return transaction(async tx=>{await query(`UPDATE StripeCheckoutAttempts SET Status='review_required' WHERE OrderId=@p0 AND Status IN ('creating','pending')`,[orderId],tx);});}
 async owned(userId,id){const x=await load(id);if(!x||x.order.user_id!==userId)fail(404,'Order not found');return x;}
 async ownedBySession(userId,sessionId){const x=await row('SELECT OrderId AS id FROM StripeCheckoutAttempts WHERE SessionId=@p0 AND UserId=@p1',[sessionId,userId]);if(!x)fail(404,'Checkout session not found');const order=await load(x.id);if(!order||order.order.user_id!==userId)fail(404,'Checkout session not found');return order.order;}
 async bySession(sessionId){const a=await row('SELECT OrderId AS id FROM StripeCheckoutAttempts WHERE SessionId=@p0',[sessionId]);return a?load(a.id):null;}
 async status(userId,id){const x=await this.owned(userId,id);const pay=await row('SELECT Status AS status FROM Payments WHERE OrderId=@p0',[id]);return {...x,payment_status:pay?.status??'pending'};}
 async settle(id,session,eventId=null,externalTx=null){const run=async tx=>{
  const x=await load(id,tx);if(!x)fail(404,'Order not found');const {order,attempt}=x;
  if(!checkSession(session,order,attempt,{settlement:true}))return 'not_paid';
  const intent=session.payment_intent;if(typeof intent!=='string'||!intent.startsWith('pi_'))fail(409,'Payment intent missing');
  const pay=await row('SELECT ProviderReference AS reference,Status AS status FROM Payments WHERE OrderId=@p0',[id],tx);
  if(order.status==='completed'&&attempt.status==='paid'&&pay?.reference===intent&&pay.status==='approved_test')return 'already_paid';
  if(pay||order.status!=='pending_payment'||!['creating','pending','review_required'].includes(attempt.status))fail(409,'Order requires manual reconciliation');
  if(await affected(`UPDATE StripeCheckoutAttempts SET Status='processing' WHERE Id=@p0 AND Status=@p1`,[attempt.id,attempt.status],tx)!==1)fail(409,'Concurrent settlement');
  await query(`INSERT INTO Payments(OrderId,Method,ProviderReference,CardLast4,Amount,Status) VALUES (@p0,'stripe_test',@p1,NULL,@p2,'approved_test')`,[id,intent,order.total],tx);
  if(await affected(`UPDATE Orders SET Status='completed' WHERE Id=@p0 AND Status='pending_payment'`,[id],tx)!==1)fail(409,'Order settlement state changed; transaction rolled back');
  if(await affected(`UPDATE StripeCheckoutAttempts SET Status='paid' WHERE Id=@p0 AND Status='processing'`,[attempt.id],tx)!==1)fail(409,'Attempt settlement state changed; transaction rolled back');
  const items=(await query('SELECT ProductId AS id FROM OrderItems WHERE OrderId=@p0',[id],tx)).recordset;
  await outbox(tx,'payment.completed',id,items.map(i=>i.id),eventId);
  return 'settled';
 };return externalTx?run(externalTx):transaction(run);}
 async release(id,session,{eventId=null,failed=false}={},externalTx=null){const run=async tx=>{
  const x=await load(id,tx);if(!x)fail(404,'Order not found');const {order,attempt}=x;
  // Async failure requires independently validated unpaid session; expiration requires expired/unpaid.
  checkSession(session,order,attempt,{expiration:!failed});
  if(failed&&session.payment_status!=='unpaid')fail(409,'Payment not verified unpaid');
  const target=failed?'failed':'expired';
  if(order.status===target&&attempt.status===target)return 'already_'+target;
  if(order.status!=='pending_payment'||!['pending','review_required'].includes(attempt.status))fail(409,'Checkout cannot safely release stock');
  if(await row('SELECT Id AS id FROM Payments WHERE OrderId=@p0',[id],tx))fail(409,'Existing payment requires manual review');
  if(await affected(`UPDATE StripeCheckoutAttempts SET Status='processing' WHERE Id=@p0 AND Status=@p1`,[attempt.id,attempt.status],tx)!==1)fail(409,'Concurrent checkout finalization');
  const items=(await query('SELECT ProductId AS id,Quantity AS qty FROM OrderItems WHERE OrderId=@p0',[id],tx)).recordset;
  for(const item of items){if(await affected('UPDATE Products SET Stock=Stock+@p0 WHERE Id=@p1',[item.qty,item.id],tx)!==1)fail(409,'Unable to restore reserved stock; transaction rolled back');}
  if(await affected(`UPDATE Orders SET Status=@p0 WHERE Id=@p1 AND Status='pending_payment'`,[target,id],tx)!==1)fail(409,'Order release state changed; transaction rolled back');
  if(await affected(`UPDATE StripeCheckoutAttempts SET Status=@p0 WHERE Id=@p1 AND Status='processing'`,[target,attempt.id],tx)!==1)fail(409,'Attempt release state changed; transaction rolled back');
  await outbox(tx,'inventory.released',id,items.map(i=>i.id),eventId);
  return target;
 };return externalTx?run(externalTx):transaction(run);}
 async processEvent(event){
  if(!event||typeof event.id!=='string'||!event.id.startsWith('evt_')||typeof event.type!=='string')fail(400,'Invalid Stripe event');
  try{return await transaction(async tx=>{
  if(await row('SELECT Id FROM StripeCheckoutEvents WHERE EventId=@p0',[event.id],tx))return {received:true,duplicate:true};
  if(event.livemode!==false)fail(400,'Live events rejected');
  const types=['checkout.session.completed','checkout.session.async_payment_succeeded','checkout.session.async_payment_failed','checkout.session.expired'];
  if(types.includes(event.type)){
   const session=event.data?.object;
   const attempt=await row('SELECT OrderId AS id FROM StripeCheckoutAttempts WHERE SessionId=@p0',[session?.id],tx);
   if(attempt){
    if(['checkout.session.completed','checkout.session.async_payment_succeeded'].includes(event.type)){
     if(session.payment_status==='paid'){const current=await load(attempt.id,tx);if(current?.order.status==='pending_payment')await this.settle(attempt.id,session,event.id,tx);}
    }else if(event.type==='checkout.session.expired'){
     {const current=await load(attempt.id,tx);if(current?.order.status==='pending_payment')await this.release(attempt.id,session,{eventId:event.id},tx);}
    }else if(event.type==='checkout.session.async_payment_failed'){
     {const current=await load(attempt.id,tx);if(current?.order.status==='pending_payment')await this.release(attempt.id,session,{eventId:event.id,failed:true},tx);}
    }
   }
  }
  await query('INSERT INTO StripeCheckoutEvents(EventId,EventType) VALUES (@p0,@p1)',[event.id,event.type],tx);
  return {received:true};
  });}catch(e){
   const number=e?.number??e?.originalError?.info?.number;
   if([2601,2627].includes(Number(number))){
    const duplicate=await row('SELECT Id AS id FROM StripeCheckoutEvents WHERE EventId=@p0',[event.id]);
    if(duplicate)return {received:true,duplicate:true};
   }
   throw e;
  }
 }
}
