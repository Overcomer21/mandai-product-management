import {query,transaction} from './db.js';
import {fail} from '../shared/errors.js';
import {cents,amount,deliveryFeeCents} from '../domain/money.js';
const duplicate=e=>e.number===2627||e.number===2601||[2627,2601].includes(e.originalError?.info?.number);
const busy=e=>[1205,1222].includes(e.number)||[1205,1222].includes(e.originalError?.info?.number);
export class SqlOrderRepository {
 async existing(userId,key){return (await query('SELECT Id AS id, RequestFingerprint AS fingerprint, TotalAmount AS total, Status AS status FROM Orders WHERE UserId=@p0 AND IdempotencyKey=@p1',[userId,key])).recordset[0]||null;}
 async item(orderId){return (await query('SELECT TOP 1 ProductId AS product_id, Quantity AS quantity FROM OrderItems WHERE OrderId=@p0 ORDER BY Id',[orderId])).recordset[0];}
 async payment(orderId){return (await query('SELECT Status AS status FROM Payments WHERE OrderId=@p0',[orderId])).recordset[0]||null;}
 async purchase(userId,key,fp,body){
  try{return await transaction(async tx=>{
   const p=(await query('SELECT Price AS price FROM Products WHERE Id=@p0 AND IsActive=1',[body.product_id],tx)).recordset[0];if(!p)fail(404,'Product not available');
   const total=amount(cents(p.price)*body.quantity);
   const r=await query("INSERT INTO Orders(UserId, IdempotencyKey, RequestFingerprint, TotalAmount, Status) OUTPUT INSERTED.Id AS id VALUES (@p0,@p1,@p2,@p3,'completed')",[userId,key,fp,total],tx);
   const id=r.recordset[0].id;
   const reduced=await query('UPDATE Products SET Stock=Stock-@p0 WHERE Id=@p1 AND IsActive=1 AND Stock>=@p0',[body.quantity,body.product_id],tx);
   if(reduced.rowsAffected[0]!==1)fail(409,'Insufficient stock');
   await query('INSERT INTO OrderItems(OrderId,ProductId,Quantity,UnitPrice) VALUES (@p0,@p1,@p2,@p3)',[id,body.product_id,body.quantity,p.price],tx);
   return {order_id:id,product_id:body.product_id,quantity:body.quantity,total_amount:total,status:'completed',replayed:false};
  });}catch(e){if(duplicate(e))fail(409,'Idempotency conflict');if(busy(e))fail(503,'Database temporarily busy; retry with the same Idempotency-Key');throw e;}
 }
 async checkout(userId,key,fp,body){
  try{return await transaction(async tx=>{
   const r=await query("INSERT INTO Orders(UserId,IdempotencyKey,RequestFingerprint,TotalAmount,Status,DeliveryAddress) OUTPUT INSERTED.Id AS id VALUES (@p0,@p1,@p2,0,'completed',@p3)",[userId,key,fp,body.delivery_address],tx);
   const orderId=r.recordset[0].id;let subtotal=0;
   for(const item of [...body.items].sort((a,b)=>a.product_id-b.product_id)){
    const p=(await query('SELECT Price AS price FROM Products WHERE Id=@p0 AND IsActive=1',[item.product_id],tx)).recordset[0];if(!p)fail(404,'Product no longer available');
    const reduced=await query('UPDATE Products SET Stock=Stock-@p0 WHERE Id=@p1 AND IsActive=1 AND Stock>=@p0',[item.quantity,item.product_id],tx);if(reduced.rowsAffected[0]!==1)fail(409,`Insufficient stock for product ${item.product_id}`);
    subtotal+=cents(p.price)*item.quantity;
    await query('INSERT INTO OrderItems(OrderId,ProductId,Quantity,UnitPrice) VALUES (@p0,@p1,@p2,@p3)',[orderId,item.product_id,item.quantity,p.price],tx);
   }
   const total=amount(subtotal+deliveryFeeCents);
   await query('UPDATE Orders SET TotalAmount=@p0 WHERE Id=@p1',[total,orderId],tx);
   const {randomUUID}=await import('node:crypto');
   await query('INSERT INTO Payments(OrderId,Method,ProviderReference,CardLast4,Amount,Status) VALUES (@p0,@p1,@p2,@p3,@p4,@p5)',[orderId,body.payment_method,'DEMO-'+randomUUID().replace(/-/g,''),body.payment_method==='card_demo'?'4242':null,total,'approved_demo'],tx);
   return {order_id:orderId,status:'completed',subtotal:amount(subtotal),delivery_fee:amount(deliveryFeeCents),total_amount:total,payment_status:'approved_demo',replayed:false};
  });}catch(e){if(duplicate(e))fail(409,'Checkout idempotency conflict');if(busy(e))fail(503,'Database busy, retry with same Idempotency-Key');throw e;}
 }
 async myOrders(userId){return (await query('SELECT Id AS id, TotalAmount AS total_amount, Status AS status FROM Orders WHERE UserId=@p0 ORDER BY Id DESC',[userId])).recordset.map(x=>({...x,total_amount:amount(cents(x.total_amount))}));}
 async details(userId){
  // Query one order per result set only where necessary; three bounded queries per batch.
  const orders=(await query('SELECT Id AS id, TotalAmount AS total_amount, Status AS status FROM Orders WHERE UserId=@p0 ORDER BY Id DESC',[userId])).recordset;
  const result=[];
  for(let start=0;start<orders.length;start+=500){
   const chunk=orders.slice(start,start+500),ids=chunk.map(x=>x.id),place=ids.map((_,i)=>'@p'+i).join(',');
   const items=(await query(`SELECT oi.OrderId AS order_id, oi.ProductId AS product_id, oi.Quantity AS quantity, oi.UnitPrice AS unit_price, p.Name AS name FROM OrderItems oi LEFT JOIN Products p ON p.Id=oi.ProductId WHERE oi.OrderId IN (${place})`,ids)).recordset;
   const pays=(await query(`SELECT OrderId AS order_id, Method AS method, Status AS status FROM Payments WHERE OrderId IN (${place})`,ids)).recordset;
   for(const o of chunk){const pay=pays.find(p=>p.order_id===o.id);result.push({id:o.id,total_amount:amount(cents(o.total_amount)),status:o.status,payment_status:pay?.status??'not_recorded',payment_method:pay?.method??null,items:items.filter(i=>i.order_id===o.id).map(i=>({product_id:i.product_id,name:i.name,quantity:i.quantity,unit_price:amount(cents(i.unit_price))}))});}
  }return result;
 }
}
