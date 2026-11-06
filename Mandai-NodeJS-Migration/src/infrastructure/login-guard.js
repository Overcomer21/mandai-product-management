import {createHash} from 'node:crypto';
import {createClient} from 'redis';
import {fail} from '../shared/errors.js';

const WINDOW_SECONDS = 900;
const ACCOUNT_IP_LIMIT = 5;
const IP_LIMIT = 30;
const ACCOUNT_LIMIT = 15;
// Atomic INCR+TTL avoids permanent locks when concurrent login attempts arrive.
const incrementWithExpiry = `
  local count = redis.call('INCR', KEYS[1])
  if count == 1 or redis.call('TTL', KEYS[1]) < 0 then
    redis.call('EXPIRE', KEYS[1], ARGV[1])
  end
  return count
`;

export class RedisLoginGuard {
  constructor(url, client = null) {
    this.client = client ?? createClient({url});
    this.client.on('error', () => {}); // Operations fail closed when Redis is unavailable.
    this.connecting = null;
  }
  async ensure() {
    if (this.client.isReady) return;
    if (!this.connecting && !this.client.isOpen) {
      this.connecting = this.client.connect().finally(() => {this.connecting = null;});
    }
    if (this.connecting) await this.connecting;
    if (!this.client.isReady) fail(503, 'Login temporarily unavailable');
  }
  hash(value) { return createHash('sha256').update(value).digest('hex'); }
  keys(email, ip) {
    const address = String(ip || 'unknown');
    const normalizedEmail = String(email).toLowerCase().trim();
    return {
      pair: `login:pair:${this.hash(`${normalizedEmail}|${address}`)}`,
      ip: `login:ip:${this.hash(address)}`,
      account: `login:account:${this.hash(normalizedEmail)}`,
    };
  }
  // Retain existing key helper for older callers, while using scoped limits below.
  key(email, ip) { return this.keys(email, ip).pair; }
  async check(email, ip) {
    await this.ensure();
    const keys = this.keys(email, ip);
    const [pair, address, account] = await Promise.all([
      this.client.get(keys.pair), this.client.get(keys.ip), this.client.get(keys.account),
    ]);
    if (Number(pair || 0) >= ACCOUNT_IP_LIMIT ||
        Number(address || 0) >= IP_LIMIT ||
        Number(account || 0) >= ACCOUNT_LIMIT) {
      fail(429, 'Too many failed login attempts');
    }
  }
  async failure(email, ip) {
    await this.ensure();
    const keys = this.keys(email, ip);
    // All counters share the same window; increment atomically per key.
    for (const key of [keys.pair, keys.ip, keys.account]) {
      await this.client.eval(incrementWithExpiry, {keys: [key], arguments: [String(WINDOW_SECONDS)]});
    }
  }
  async success(email, ip) {
    await this.ensure();
    const keys = this.keys(email, ip);
    // Keep IP and account failure windows intact to prevent credential stuffing
    // being reset by a successful login on another account.
    await this.client.del(keys.pair);
  }
}
