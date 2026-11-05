import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import {SqlCatalogRepository} from './infrastructure/catalog-repository.js';
import {SqlIdentityRepository} from './infrastructure/identity-repository.js';
import {SqlOrderRepository} from './infrastructure/order-repository.js';
import {CatalogService} from './application/catalog-service.js';
import {IdentityService} from './application/identity-service.js';
import {OrderService} from './application/order-service.js';
import {RedisCatalogCache} from './infrastructure/cache.js';
import {RedisLoginGuard} from './infrastructure/login-guard.js';
import {buildRouter} from './interfaces/routes.js';
import {connect} from './infrastructure/db.js';
import {SqlStripeRepository} from './infrastructure/stripe-repository.js';
import {StripeGateway} from './infrastructure/stripe-gateway.js';
import {StripeCheckoutService} from './application/stripe-checkout-service.js';
const mode=process.env.SERVICE_MODE||'all';
const cache=process.env.REDIS_URL?new RedisCatalogCache(process.env.REDIS_URL,Number(process.env.CATALOG_CACHE_TTL_SECONDS||5)):null;
const guard=process.env.LOGIN_GUARD_REDIS_URL?new RedisLoginGuard(process.env.LOGIN_GUARD_REDIS_URL):null;
const services={catalog:new CatalogService(new SqlCatalogRepository(),cache),identity:new IdentityService(new SqlIdentityRepository(),guard),orders:new OrderService(new SqlOrderRepository(),cache),stripeCheckout:new StripeCheckoutService(new SqlStripeRepository(),new StripeGateway(),cache)};
export function createApp(){
 const app=express();app.disable('x-powered-by');app.use(cors({origin:(process.env.CORS_ORIGINS||'http://localhost:3000,http://localhost:8080').split(','),methods:['GET','POST','PUT','DELETE'],allowedHeaders:['Authorization','Content-Type','Idempotency-Key']}));
 if(mode==='all'||mode==='commerce')app.post('/api/stripe-checkout/webhook',express.raw({type:'application/json',limit:'256kb'}),async(req,res,next)=>{try{if(process.env.STRIPE_NODE_WRITES_ENABLED!=='true')return res.status(503).json({detail:'Node Stripe writes disabled pending integration validation'});res.json(await services.stripeCheckout.webhook(req.body,req.headers['stripe-signature']))}catch(e){next(e)}});
 app.use(express.json({limit:'256kb'}));
 app.get('/health',async(req,res)=>{try{await connect();res.status(200).json({status:'ok'});}catch{res.status(503).json({status:'unavailable'});}});
 app.use(buildRouter(services,mode));
 // Important: unfinished endpoints return explicit status, never simulate successful payment.
 app.use((req,res)=>res.status(404).json({detail:'Not Found'}));
 app.use((err,req,res,next)=>{if(Number.isInteger(err.status)&&err.status>=400&&err.status<=599)return res.status(err.status).json({detail:err.detail||err.message});if(err.type==='entity.parse.failed')return res.status(422).json({detail:'Invalid JSON'});console.error('Request failed:',err.code||err.name||'unknown');res.status(500).json({detail:'Internal server error'});});
 return app;
}
if(process.argv[1]&&import.meta.url===new URL('file://'+process.argv[1]).href){createApp().listen(Number(process.env.PORT||8000),'0.0.0.0',()=>console.log('Mandai Node API listening'));}
