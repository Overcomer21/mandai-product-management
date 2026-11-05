import {createClient} from 'redis';

// Read-through catalog cache. One flight per key per Node.js process prevents
// duplicate SQL reads on simultaneous misses. Redis keys/TTL remain unchanged.
export class RedisCatalogCache {
  constructor(url, ttl = 5, client = null) {
    this.client = client ?? createClient({url});
    this.ttl = ttl;
    this.connectPromise = null;
    this.inflight = new Map();
    this.client.on('error', () => {});
  }

  async ensure() {
    if (this.client.isReady) return true;
    if (this.connectPromise) return this.connectPromise;
    if (this.client.isOpen) return false; // connected but temporarily not ready
    this.connectPromise = this.client.connect()
      .then(() => Boolean(this.client.isReady))
      .catch(() => false)
      .finally(() => { this.connectPromise = null; });
    return this.connectPromise;
  }

  async getOrLoad(key, load) {
    let cacheKey = null;
    if (await this.ensure()) {
      try {
        const generation = (await this.client.get('mandai:catalog:generation')) || '0';
        cacheKey = `mandai:catalog:${generation}:${key}`;
        const existing = await this.client.get(cacheKey);
        if (existing !== null) return JSON.parse(existing);
      } catch {
        // Redis unavailable or corrupt value: fall back to SQL without retrying SQL.
        cacheKey = null;
      }
    }

    const flightKey = cacheKey ?? `local:${key}`;
    const active = this.inflight.get(flightKey);
    if (active) return active;

    const task = (async () => {
      // Do not catch loader errors: the repository must be executed at most once.
      const value = await load();
      if (cacheKey !== null) {
        try { await this.client.set(cacheKey, JSON.stringify(value), {EX: this.ttl}); }
        catch { /* A cache write failure must not repeat a successful SQL read. */ }
      }
      return value;
    })();

    this.inflight.set(flightKey, task);
    try { return await task; }
    finally {
      if (this.inflight.get(flightKey) === task) this.inflight.delete(flightKey);
    }
  }

  async invalidate() {
    // Preserve generation-based invalidation contract used by other services.
    if (await this.ensure()) {
      try { await this.client.incr('mandai:catalog:generation'); }
      catch { /* Existing fail-open behavior; production needs an alert/policy. */ }
    }
    // A local in-flight result should not be shared by requests after invalidation.
    this.inflight.clear();
  }
}
