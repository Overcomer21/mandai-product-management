/**
 * Mandai Node.js overselling integration test.
 * Uses ONE customer JWT to simulate 1000 independent checkout attempts (NOT 1000 separate users).
 * Does not touch GitHub, source code, or database schema.
 * Side effects with --run: inserts orders/attempts/outbox, reserves stock, creates Stripe TEST sessions.
 * With --cleanup: expires each successful unpaid Stripe session and attempts stock restoration.
 */
import { randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';

const argv = new Set(process.argv.slice(2));
const run = argv.has('--run');
const cleanup = argv.has('--cleanup');
const help = argv.has('--help');
const base = (process.env.MANDAI_API_BASE || 'http://127.0.0.1:51872').replace(/\/$/, '');
const n = Number(process.env.TEST_REQUESTS || '1000');
const concurrency = Number(process.env.TEST_CONCURRENCY || '1000');
const productId = 32;
const expectedOpeningStock = 29;
const maxTimeoutMs = 120000;
const token = process.env.TEST_JWT || '';
const retryGuard = randomUUID();

if(help){
  console.log('Usage: node mandai_overselling_1000.mjs [--run] [--cleanup]');
  console.log('Environment: TEST_JWT, TEST_REQUESTS (default 1000), TEST_CONCURRENCY (default 1000), MANDAI_API_BASE');
  console.log('Without --run: read-only preflight. --cleanup requires --run.');
  process.exit(0);
}
if(!Number.isSafeInteger(n)||n<1||n>1000 || !Number.isSafeInteger(concurrency)||concurrency<1||concurrency>1000){
  console.error('Invalid TEST_REQUESTS or TEST_CONCURRENCY, accepted range 1..1000');process.exit(2);
}
if(cleanup&&!run){console.error('--cleanup requires --run');process.exit(2);}
if(!token){console.error('TEST_JWT not found. In SAME PowerShell session: $env:TEST_JWT = $token');process.exit(2);}
if(!base.startsWith('http://127.0.0.1:') && !base.startsWith('http://localhost:')){
  console.error('For safety, API base must be a local loopback address.');process.exit(2);
}
const auth = { Authorization:`Bearer ${token}` };
const jsonHeaders = {...auth, 'Content-Type':'application/json'};

async function call(url, options={}) {
  try {
    const res = await fetch(`${base}${url}`, {signal:AbortSignal.timeout(maxTimeoutMs), ...options});
    const raw = await res.text();
    let data;
    try{data=JSON.parse(raw);}catch{data={detail:raw.slice(0,200)}}
    return {http:res.status, data};
  } catch(e) { return {http:0, error:String(e?.message||e)}; }
}

function stockValue(p){return p?.Stock??p?.stock??p?.data?.Stock??p?.data?.stock;}
async function product(){
  const r = await call(`/api/products/${productId}`);
  if(r.http!==200) throw Error(`Product GET failed HTTP ${r.http}: ${JSON.stringify(r.data||r.error)}`);
  const stock=Number(stockValue(r.data));
  if(!Number.isInteger(stock))throw Error('Cannot parse product stock from GET response; stop without writes.');
  return {stock, data:r.data};
}
async function checkAccount(){
  const r=await call('/api/account/me',{headers:auth});
  if(r.http!==200)throw Error(`Account API HTTP ${r.http}; login again before test`);
  return r.data;
}

function classify(item){
  if(item.http===201 && Number.isInteger(Number(item.data?.order_id)) && item.data?.session_id?.startsWith('cs_test_')) return 'created';
  if(item.http===409 && /insufficient stock/i.test(String(item.data?.detail||''))) return 'out_of_stock';
  if(item.http===429) return 'rate_limited';
  if(item.http===0) return 'network_uncertain';
  if(item.http>=500) return 'server_uncertain';
  return 'unexpected';
}

async function main(){
  console.log(`Base=${base}, product=${productId}, requests=${n}, concurrency=${concurrency}`);
  await checkAccount();
  console.log('JWT accepted: yes (not displayed)');
  const before=await product();
  console.log(`Opening stock: ${before.stock}; expected: ${expectedOpeningStock}`);
  if(before.stock!==expectedOpeningStock){
    console.error(`STOP: Product 32 stock is not 29. There may be existing reservations or other activity.`);process.exitCode=2;return;
  }
  if(!run){
    console.log('READ-ONLY PREFLIGHT PASS. No checkout attempted.');
    console.log('To run intentional REAL SQL writes + Stripe test sessions: node mandai_overselling_1000.mjs --run --cleanup');
    return;
  }
  if(process.env.CONFIRM_LIVE_DB_LOAD!=='YES'){
    console.error('STOP: Set $env:CONFIRM_LIVE_DB_LOAD="YES" to acknowledge REAL MandaiDB writes.');process.exitCode=2;return;
  }
  console.log('WARNING: This will create real orders and Stripe TEST sessions; do not pay them.');
  const body=JSON.stringify({items:[{product_id:productId,quantity:1}],delivery_address:'Mandai integration load test - not an actual delivery address'});
  let next=0;
  const results=Array.from({length:n});
  let inFlight=0, highWater=0;
  const start=performance.now();
  async function worker(){
    while(true){
      const index=next++;
      if(index>=n)return;
      const idem=`oversell32-${retryGuard}-${String(index).padStart(4,'0')}`;
      inFlight++; highWater=Math.max(highWater,inFlight);
      try{
        const r=await call('/api/stripe-checkout/sessions',{method:'POST',headers:{...jsonHeaders,'Idempotency-Key':idem},body});
        results[index]={index, idem, ...r};
      }finally{inFlight--}
    }
  }
  await Promise.all(Array.from({length:Math.min(concurrency,n)},()=>worker()));
  const elapsed=performance.now()-start;
  const groups={created:[],out_of_stock:[],rate_limited:[],network_uncertain:[],server_uncertain:[],unexpected:[]};
  for(const r of results)groups[classify(r)].push(r);
  const after=await product();
  console.log('\n===== LIVE OVERSOLD TEST RESULTS =====');
  console.log(`Requests=${n}; elapsed_ms=${elapsed.toFixed(0)}; peak_in_flight=${highWater}`);
  for(const [name,entries] of Object.entries(groups))console.log(`${name}: ${entries.length}`);
  console.log(`Stock: ${before.stock} -> ${after.stock}`);
  console.log('Confirmed order IDs:',groups.created.map(x=>x.data.order_id).join(', ')||'(none)');
  for(const r of [...groups.network_uncertain,...groups.server_uncertain,...groups.unexpected].slice(0,12)){
    console.log('Non-success sample:',JSON.stringify({index:r.index,http:r.http,detail:r.data?.detail||r.error,idem:r.idem}));
  }
  if(after.stock<0)console.error('CRITICAL FAILURE: NEGATIVE INVENTORY');
  const expected=before.stock - groups.created.length;
  if(after.stock!==expected){console.error(`RECONCILIATION REQUIRED: observed stock=${after.stock}, expected from confirmed success=${expected}; uncertain attempts may have reserved stock.`);}
  else console.log(`Stock matches confirmed sessions (${after.stock}).`);
  const strictPass=groups.created.length===29 && groups.out_of_stock.length===n-29 &&
    groups.rate_limited.length===0 && groups.network_uncertain.length===0 && groups.server_uncertain.length===0 && groups.unexpected.length===0 && after.stock===0;
  console.log(`STRICT OVERSOLD CHECK: ${strictPass?'PASS':'INCONCLUSIVE/FAIL (inspect above)'}`);

  if(cleanup){
    console.log('\n===== CANCELLATION OF CONFIRMED UNPAID TEST SESSIONS =====');
    const orders=groups.created.map(r=>r.data.order_id);
    let restored=0,failed=0;
    // Deliberately sequential: easier to diagnose partial failure and avoid further contention.
    for(const id of orders){
      const r=await call(`/api/stripe-checkout/orders/${id}/cancel`,{method:'POST',headers:jsonHeaders,body:'{}'});
      if(r.http===200 && r.data?.status==='expired'){restored++}
      else{failed++;console.error(`CANCEL NEEDS REVIEW: order=${id}, HTTP=${r.http}, detail=${r.data?.detail||r.error||r.data?.status}`)}
    }
    console.log(`Confirmed cancellations=${restored}; failed/uncertain=${failed}`);
    const final=await product();
    console.log(`Final Product 32 stock: ${final.stock} (opening ${before.stock})`);
    if(final.stock!==before.stock)console.error('ATTENTION: stock not fully restored. Investigate pending/unknown checkout attempts. DO NOT reset stock manually.');
    else console.log('Stock restored to opening value (assuming no other concurrent buyers).');
  } else console.log('WARNING: Unpaid sessions remain OPEN and inventory remains RESERVED; do not leave sessions unattended.');
  if(!strictPass)process.exitCode=1;
}

main().catch(e=>{console.error('STOP:',e.message);process.exitCode=2;});
