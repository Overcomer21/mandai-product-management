// Read-only benchmark against MandaiDB. Run inside commerce/catalog Docker image with Node stdin:
//   Get-Content -Raw .\sql_catalog_benchmark.mjs | docker compose ... exec -T catalog1 node --input-type=module -
// Uses direct SQL and records QUERY client elapsed time, not HTTP response time.
import {performance} from 'node:perf_hooks';
import {query} from './src/infrastructure/db.js';
const cats=[null,'Apparel'];
const sorts=[['Default','Id'],['Name','Name, Id'],['Price low','Price ASC, Id'],['Price high','Price DESC, Id']];
const repeat=5;
const results=[];
console.log('READ-ONLY MandaiDB catalog benchmark: 8 scenarios x 5 executions');
for(const category of cats)for(const [sort,order] of sorts){
 const timings=[];
 for(let i=0;i<repeat;i++){
  const params=category?[category]:[];
  const where=category?'WHERE IsActive=1 AND Category=@p0':'WHERE IsActive=1';
  const statement=`SELECT Id, Name, Category, Price, Stock, IsActive FROM dbo.Products ${where} ORDER BY ${order} OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY`;
  const start=performance.now();const r=await query(statement,params);timings.push(performance.now()-start);
  if(!Array.isArray(r.recordset))throw Error('Expected SQL recordset');
 }
 const min=Math.min(...timings),max=Math.max(...timings),avg=timings.reduce((a,b)=>a+b,0)/repeat;
 const entry={category:category??'All',sort,executions:repeat,min_ms:+min.toFixed(2),avg_ms:+avg.toFixed(2),max_ms:+max.toFixed(2)};
 results.push(entry);console.log(JSON.stringify(entry));
}
console.log(`SQL EXECUTIONS=${results.length*repeat} PASS; Results are not the same benchmark query as the FastAPI report; compare cautiously.`);
