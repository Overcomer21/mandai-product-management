import {createHash} from 'node:crypto';
import {createClient} from 'redis';
import {fail} from '../shared/errors.js';
export class RedisLoginGuard{
 constructor(url){this.client=createClient({url});this.client.on('error',()=>{});this.connecting=null;}
 async ensure(){if(this.client.isOpen)return;this.connecting??=this.client.connect().finally(()=>this.connecting=null);await this.connecting;}
 key(email,ip){return 'login:'+createHash('sha256').update(email+'|'+ip).digest('hex');}
 async check(email,ip){await this.ensure();const n=Number(await this.client.get(this.key(email,ip))||0);if(n>=5)fail(429,'Too many failed login attempts');}
 async failure(email,ip){await this.ensure();const key=this.key(email,ip);const n=await this.client.incr(key);if(n===1)await this.client.expire(key,900);}
 async success(email,ip){await this.ensure();await this.client.del(this.key(email,ip));}
}
