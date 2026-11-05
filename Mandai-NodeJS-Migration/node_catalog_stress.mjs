#!/usr/bin/env node
// Mandai Node.js catalog stress tester. READ-ONLY: GET /api/products and /health only.
import {performance} from 'node:perf_hooks';
import fs from 'node:fs';
import path from 'node:path';

const BASE = (process.env.MANDAI_BASE || 'http://127.0.0.1:51872').replace(/\/$/, '');
const LEVELS = [10,20,50,100,200,300,400,500,600,700,800,900,1000,1100,1200,1300,1400,1500,1600,1700,1800,1900,2000];
const args=process.argv.slice(2);
const arg=(name, fallback)=>{const i=args.indexOf(name); return i<0?fallback:args[i+1];};
const all=args.includes('--all');
const level=Number(arg('--level',10));
const timeout=Number(arg('--timeout-ms',30000));
const targetP95=Number(arg('--p95-ms',2500));
const out=arg('--out','');
const url=`${BASE}/api/products`;
if(!Number.isSafeInteger(level)||level<1||level>2000||!Number.isSafeInteger(timeout)||timeout<1000||!Number.isFinite(targetP95)||targetP95<=0){console.error('Bad options');process.exit(2)}

async function getOne(target){
 const t0=performance.now();
 try{
   const res=await fetch(target,{method:'GET',headers:{accept:'application/json'},signal:AbortSignal.timeout(timeout),cache:'no-store'});
   // Consume the entire body, matching finite-response workload.
   const body=await res.text();
   let valid=false;
   if(res.status===200){try{const json=JSON.parse(body);valid=Array.isArray(json);}catch{}}
   return {status:res.status,ok:res.status===200&&valid,ms:performance.now()-t0,error:valid?'':res.status===200?'INVALID_JSON_OR_NON_ARRAY':''};
 }catch(e){return {status:0,ok:false,ms:performance.now()-t0,error:e?.name||'FETCH_ERROR'};}
}
function percentile(values,p){if(!values.length)return null;const s=[...values].sort((a,b)=>a-b);const idx=(s.length-1)*p;const low=Math.floor(idx),high=Math.ceil(idx);return s[low]+(s[high]-s[low])*(idx-low);}
async function health(){try{const r=await fetch(`${BASE}/health`,{signal:AbortSignal.timeout(5000)});await r.arrayBuffer();return r.status;}catch{return 0;}}
async function run(n){
  // Launch n one-shot requests in a burst. An HTTP client may throttle sockets,
  // so this is not a measurement of n established TCP connections.
  const start=performance.now();const results=await Promise.all(Array.from({length:n},()=>getOne(url)));const elapsed=performance.now()-start;
  const ok=results.filter(x=>x.ok).length;const failures=results.length-ok;
  const statuses={};for(const r of results){const key=r.status||r.error||'NETWORK';statuses[key]=(statuses[key]||0)+1;}
  const p95=percentile(results.map(x=>x.ms),0.95);
  const hs=await health();
  const pass=failures===0&&p95<=targetP95&&hs===200;
  const data={level:n,requests:n,http200_valid_json:ok,errors:failures,statuses,elapsed_ms:+elapsed.toFixed(2),rps:+(n/(elapsed/1000)).toFixed(2),p50_ms:+percentile(results.map(x=>x.ms),.5).toFixed(2),p95_ms:+p95.toFixed(2),p99_ms:+percentile(results.map(x=>x.ms),.99).toFixed(2),max_ms:+Math.max(...results.map(x=>x.ms)).toFixed(2),health_status:hs,p95_target_ms:targetP95,result:pass?'PASS':'FAIL'};
  console.log(`level=${n}: ${ok}/${n} HTTP200+validJSON; errors=${failures}; RPS=${data.rps}; P95=${data.p95_ms}ms; health=${hs}; ${data.result}`);
  if(failures)console.log('  statuses:',JSON.stringify(statuses));
  return data;
}
console.log(`READ-ONLY Mandai Node.js GET /api/products | BASE=${BASE} | timeout=${timeout}ms | target P95<=${targetP95}ms`);
let results=[];
for(const n of (all?LEVELS:[level])){
 const r=await run(n);results.push(r);
 if(r.result==='FAIL'&&all&&!args.includes('--continue-on-fail')){console.error('Stopping after failure; pass --continue-on-fail to run remaining levels.');break;}
}
const report={test:'Node.js catalog finite-burst GET stress',source:'node_catalog_stress.mjs',timestamp:new Date().toISOString(),base:BASE,endpoint:'/api/products',read_only:true,levels:results,summary:{stages:results.length,passed:results.filter(r=>r.result==='PASS').length,failed:results.filter(r=>r.result==='FAIL').length,total_requests:results.reduce((a,r)=>a+r.requests,0),total_successes:results.reduce((a,r)=>a+r.http200_valid_json,0)}};
if(out){fs.mkdirSync(path.dirname(path.resolve(out)),{recursive:true});fs.writeFileSync(out,JSON.stringify(report,null,2));console.log('Results:',out);}
console.log('SUMMARY',JSON.stringify(report.summary));
if(report.summary.failed)process.exitCode=1;
