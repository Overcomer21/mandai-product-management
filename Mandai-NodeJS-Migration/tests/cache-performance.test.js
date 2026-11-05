import test from 'node:test';
import assert from 'node:assert/strict';
import {RedisCatalogCache} from '../src/infrastructure/cache.js';

class FakeRedis {
  constructor() { this.isOpen = false; this.isReady = false; this.map = new Map(); this.calls = []; this.failRead = false; this.failWrite = false; this.failConnect = false; }
  on() { return this; }
  async connect() { if (this.failConnect) throw new Error('connect failed'); this.isOpen = true; this.isReady = true; }
  async get(key) { this.calls.push(['get',key]); if (this.failRead) throw new Error('get failed'); return this.map.get(key) ?? null; }
  async set(key,value) { this.calls.push(['set',key]); if (this.failWrite) throw new Error('set failed'); this.map.set(key,value); }
  async incr(key) { this.calls.push(['incr',key]); const next=Number(this.map.get(key) ?? 0)+1; this.map.set(key,String(next)); return next; }
}

const make = () => { const client = new FakeRedis(); return {client, cache:new RedisCatalogCache('redis://fake:6379',5,client)}; };

test('concurrent misses execute loader once and reuse cached result', async () => {
  const {cache,client}=make(); let loads=0;
  const values=await Promise.all(Array.from({length:200},()=>cache.getOrLoad('page:{}',async()=>{loads++;await new Promise(resolve=>setTimeout(resolve,10));return [{id:1}];})));
  assert.equal(loads,1); assert.ok(values.every(v=>v[0].id===1));
  assert.deepEqual(await cache.getOrLoad('page:{}',async()=>{throw Error('unexpected cache miss');}),[{id:1}]);
  assert.ok(client.calls.some(([method])=>method==='set'));
});

test('Redis SET failure does not execute SQL loader twice',async()=>{
  const {cache,client}=make();client.failWrite=true;let loads=0;
  assert.deepEqual(await cache.getOrLoad('detail:1',async()=>{loads++;return {id:1};}),{id:1});
  assert.equal(loads,1);
});

test('SQL exception is propagated without retry',async()=>{
  const {cache}=make();let loads=0;
  await assert.rejects(cache.getOrLoad('detail:2',async()=>{loads++;throw Error('SQL unavailable');}),/SQL unavailable/);
  assert.equal(loads,1);
});

test('Redis GET failure falls back to SQL once',async()=>{
  const {cache,client}=make();client.failRead=true;let loads=0;
  assert.deepEqual(await cache.getOrLoad('detail:3',async()=>{loads++;return {id:3};}),{id:3});
  assert.equal(loads,1);
});

test('generation changes after invalidation, forcing a fresh query',async()=>{
  const {cache,client}=make();let loads=0;
  const load=async()=>({value:++loads});
  assert.equal((await cache.getOrLoad('detail:4',load)).value,1);
  assert.equal((await cache.getOrLoad('detail:4',load)).value,1);
  await cache.invalidate();
  assert.equal((await cache.getOrLoad('detail:4',load)).value,2);
  assert.equal(client.map.get('mandai:catalog:generation'),'1');
});

test('unavailable Redis still coalesces local misses',async()=>{
  const {cache,client}=make();client.failConnect=true;let loads=0;
  const values=await Promise.all(Array.from({length:30},()=>cache.getOrLoad('page',async()=>{loads++;await new Promise(r=>setTimeout(r,5));return [1];})));
  assert.equal(loads,1);assert.equal(values.length,30);
});
