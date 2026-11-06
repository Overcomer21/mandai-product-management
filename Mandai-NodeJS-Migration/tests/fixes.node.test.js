import test from 'node:test';
import assert from 'node:assert/strict';
import { RedisLoginGuard } from '../src/infrastructure/login-guard.js';
import { RedisCatalogCache } from '../src/infrastructure/cache.js';
import { CatalogService } from '../src/application/catalog-service.js';

// Small in-memory fake implements only Redis calls exercised by the real classes.
// It does NOT prove network/Redis/Docker/SQL behavior.
class FakeRedis {
  constructor(shared) { this.shared=shared; this.isReady=true; this.isOpen=true; this.fail=false; this.failNext=false; }
  on() { return this; }
  async connect() { this.isReady=true; this.isOpen=true; }
  check(){ if(this.fail || this.failNext){this.failNext=false; throw Error('Redis unavailable');} }
  async get(key){this.check();return this.shared.has(key)?this.shared.get(key):null;}
  async set(key,value){this.check();this.shared.set(key,String(value));return 'OK';}
  async incr(key){this.check();const n=Number(this.shared.get(key)||0)+1;this.shared.set(key,String(n));return n;}
  async del(key){this.check();return this.shared.delete(key)?1:0;}
  async eval(script,{keys,arguments:args}){
    this.check();
    assert.match(script,/INCR/);assert.match(script,/EXPIRE/);
    assert.equal(Number(args[0]),900);
    return this.incr(keys[0]);
  }
}
const makeRedis=()=>new FakeRedis(new Map());
async function expectHttp(promise,status) {
  await assert.rejects(promise,error=>error?.status===status,`Expected HTTP ${status}`);
}

test('F03: key normalization, IP/account/pair key separation and no plaintext email in key',()=>{
  const guard=new RedisLoginGuard('redis://unused',makeRedis());
  const x=guard.keys(' USER@EXAMPLE.COM ','10.1.1.2');
  const y=guard.keys('user@example.com','10.1.1.2');
  assert.deepEqual(x,y);
  assert.notEqual(x.pair,x.ip); assert.notEqual(x.account,x.ip);
  assert.ok(Object.values(x).every(k=>!k.includes('user@example.com')));
});

test('F03: block account+IP after 5 failed attempts',async()=>{
  const guard=new RedisLoginGuard('redis://unused',makeRedis());
  for(let i=0;i<5;i++) {await guard.check('a@b.com','10.0.0.1');await guard.failure('a@b.com','10.0.0.1');}
  await expectHttp(guard.check('a@b.com','10.0.0.1'),429);
  await guard.check('a@b.com','10.0.0.2');
});

test('F03: 30 failures from one IP block even with different accounts',async()=>{
  const guard=new RedisLoginGuard('redis://unused',makeRedis());
  for(let i=0;i<30;i++) await guard.failure(`user${i}@example.com`,'10.0.0.9');
  await expectHttp(guard.check('new@example.com','10.0.0.9'),429);
  await guard.check('new@example.com','10.0.0.10');
});

test('F03: 15 failures on one account block across different IPs',async()=>{
  const guard=new RedisLoginGuard('redis://unused',makeRedis());
  for(let i=0;i<15;i++) await guard.failure('target@example.com',`10.0.0.${i+1}`);
  await expectHttp(guard.check('target@example.com','10.1.1.1'),429);
});

test('F03: successful login clears pair only, keeping global IP and account counters',async()=>{
  const redis=makeRedis(), guard=new RedisLoginGuard('redis://unused',redis);
  await guard.failure('a@b.com','10.0.0.1');
  const keys=guard.keys('a@b.com','10.0.0.1');
  await guard.success('a@b.com','10.0.0.1');
  assert.equal(await redis.get(keys.pair),null);
  assert.equal(await redis.get(keys.ip),'1');
  assert.equal(await redis.get(keys.account),'1');
});

test('F03: Redis operation outage does not silently allow login',async()=>{
  const redis=makeRedis(), guard=new RedisLoginGuard('redis://unused',redis);
  redis.fail=true;
  await assert.rejects(guard.check('a@b.com','10.0.0.1'));
});

test('F01: two independent catalog caches share generation and invalidate after admin update',async()=>{
  const shared=new Map();
  const readerCache=new RedisCatalogCache('redis://unused',5,new FakeRedis(shared));
  const writerCache=new RedisCatalogCache('redis://unused',5,new FakeRedis(shared));
  let value={stock:5}, loads=0;
  const loader=async()=>{loads++;return structuredClone(value)};
  assert.deepEqual(await readerCache.getOrLoad('detail:1',loader),{stock:5});
  value={stock:4};
  assert.deepEqual(await readerCache.getOrLoad('detail:1',loader),{stock:5}); // cache hit
  const catalog=new CatalogService({update:async()=>({id:1})},writerCache);
  await catalog.update(1,{stock:4});
  assert.equal(await new FakeRedis(shared).get('mandai:catalog:generation'),'1');
  assert.deepEqual(await readerCache.getOrLoad('detail:1',loader),{stock:4});
  assert.equal(loads,2);
});

test('F01: per-process in-flight cache deduplicates simultaneous SQL reads',async()=>{
  const cache=new RedisCatalogCache('redis://unused',5,makeRedis());
  let loads=0;
  const results=await Promise.all(Array.from({length:12},()=>cache.getOrLoad('page:1',async()=>{
    loads++;await new Promise(resolve=>setTimeout(resolve,15));return {items:[1]};
  })));
  assert.equal(loads,1);
  assert.ok(results.every(r=>r.items[0]===1));
});

test('F01: cache survives Redis errors via repository loader fallback',async()=>{
  const redis=makeRedis(),cache=new RedisCatalogCache('redis://unused',5,redis);
  redis.fail=true;
  let called=0;
  const data=await cache.getOrLoad('count:all',async()=>{called++;return {total:12};});
  assert.deepEqual(data,{total:12}); assert.equal(called,1);
});
