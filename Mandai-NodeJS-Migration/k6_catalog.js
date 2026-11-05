// Run with: k6 run --rps 300 -e MANDAI_BASE=http://127.0.0.1:51872 -e USERS=400 k6_catalog.js
// READ ONLY. One GET /api/products per configured VU. The global 300 RPS cap paces requests.
import http from 'k6/http';
import { check } from 'k6';
const users=Number(__ENV.USERS||400);
if(!Number.isInteger(users)||users<1||users>2000)throw new Error('USERS must be between 1 and 2000');
const base=(__ENV.MANDAI_BASE||'http://127.0.0.1:51872').replace(/\/$/,'');
export const options={
  scenarios:{catalog_once:{executor:'per-vu-iterations',vus:users,iterations:1,maxDuration:'3m'}},
  thresholds:{http_req_failed:['rate==0'],http_req_duration:['p(95)<=2500'],checks:['rate==1']},
  discardResponseBodies:false,
};
export default function(){
  const r=http.get(`${base}/api/products`,{headers:{Accept:'application/json'},timeout:'30s'});
  check(r,{'HTTP 200 and JSON product array':res=>{if(res.status!==200)return false;try{return Array.isArray(res.json())}catch{return false}}});
}
