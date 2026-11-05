// REAL SQL Server diagnostic: SELECT ONLY. No inserts, schema migration, or mock.
import 'dotenv/config';
import sql from 'mssql';
const config={server:process.env.DB_HOST,port:Number(process.env.DB_PORT),database:process.env.DB_NAME,user:process.env.DB_USER,password:process.env.DB_PASSWORD,options:{encrypt:process.env.DB_ENCRYPT==='true',trustServerCertificate:process.env.DB_TRUST_CERT==='true'},connectionTimeout:10000,requestTimeout:15000};
const spec={
 Users:['Id','Email','PasswordHash','Role'],
 Products:['Id','Name','Price','Stock','IsActive'],
 Orders:['Id','UserId','IdempotencyKey','RequestFingerprint','TotalAmount','Status','DeliveryAddress'],
 OrderItems:['Id','OrderId','ProductId','Quantity','UnitPrice'],
 Payments:['Id','OrderId','Method','ProviderReference','Amount','Status'],
 StripeCheckoutAttempts:['Id','OrderId','UserId','SessionId','CheckoutUrl','Status','AmountMinor'],
 StripeCheckoutEvents:['Id','EventId','EventType'],
 PaymentOutbox:['Id','EventId','EventType','AggregateId','Payload','PublishedAt']
};
let pool;
try{
 pool=await new sql.ConnectionPool(config).connect();
 const connection=await pool.request().query('SELECT DB_NAME() AS database_name, 1 AS ok');
 console.log('SQL authentication:',connection.recordset[0].ok===1?'PASS':'FAIL');
 console.log('Database:',connection.recordset[0].database_name);
 const result=await pool.request().query(`SELECT TABLE_NAME AS t,COLUMN_NAME AS c FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo'`);
 const names=new Map();for(const r of result.recordset){let s=names.get(r.t);if(!s){s=new Set();names.set(r.t,s)}s.add(r.c)}
 let failures=0;
 for(const [table,cols] of Object.entries(spec)){
  const found=names.get(table);const missing=cols.filter(c=>!found?.has(c));
  const status=!found?'MISSING TABLE':missing.length?'MISSING COLUMNS: '+missing.join(', '):'PASS';
  if(status!=='PASS')failures++;
  console.log(`${table}: ${status}`);
 }
 if(failures){console.error('Real SQL schema preflight FAILED. Do NOT enable Stripe writes.');process.exitCode=2;}
 else console.log('Real SQL schema preflight PASS (read-only). Payment transactions NOT tested.');
}catch(e){console.error('SQL preflight FAILED',e.code||e.name);process.exitCode=1;}
finally{if(pool)await pool.close();}
