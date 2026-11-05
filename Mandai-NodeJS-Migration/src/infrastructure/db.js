import sql from 'mssql';
let poolPromise;
export const dbTypes={sql};
export function connect(){
 if(!poolPromise){
  const config={server:process.env.DB_HOST||'localhost',port:Number(process.env.DB_PORT||1433),database:process.env.DB_NAME||'MandaiDB',user:process.env.DB_USER||'mandai_app',password:process.env.DB_PASSWORD||'',options:{encrypt:process.env.DB_ENCRYPT!=='false',trustServerCertificate:process.env.DB_TRUST_CERT==='true'},pool:{max:Number(process.env.DB_POOL_SIZE||10),min:0,idleTimeoutMillis:30000}};
  poolPromise=new sql.ConnectionPool(config).connect().catch(e=>{poolPromise=null;throw e});
 }
 return poolPromise;
}
export async function query(statement,params=[],tx=null){
 const request=tx?new sql.Request(tx):new sql.Request(await connect());
 for(let i=0;i<params.length;i++)request.input('p'+i,params[i]);
 return request.query(statement);
}
export async function transaction(fn){const pool=await connect(),tx=new sql.Transaction(pool);await tx.begin(sql.ISOLATION_LEVEL.READ_COMMITTED);try{const result=await fn(tx);await tx.commit();return result;}catch(error){try{await tx.rollback()}catch{}throw error;}}
