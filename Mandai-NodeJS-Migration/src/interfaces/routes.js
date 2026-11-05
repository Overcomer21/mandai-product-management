import express from 'express';
import {paymentReturnPage} from './payment-return.js';
import {asyncRoute,fail,parseBoolean,productInput,requireInteger,validatePage} from '../shared/errors.js';
export function buildRouter({catalog,identity,orders,stripeCheckout},mode='all'){
 const router=express.Router(), enabled=name=>mode==='all'||mode===name;
 const auth=asyncRoute(async(req,res,next)=>{req.user=await identity.authenticate(req.headers.authorization);next();});
 const admin=(req,res,next)=>req.user.role==='admin'?next():next(new (class extends Error{constructor(){super('Admin role required');this.status=403;this.detail='Admin role required';}})());
 if(enabled('catalog')){
  router.get('/api/products/categories',asyncRoute(async(req,res)=>res.json(await catalog.categories())));
  router.get('/api/products/count',asyncRoute(async(req,res)=>res.json(await catalog.count(validatePage(req.query)))));
  router.get('/api/products',asyncRoute(async(req,res)=>res.json(await catalog.page(validatePage(req.query)))));
  router.get('/api/products/:id',asyncRoute(async(req,res)=>res.json(await catalog.detail(requireInteger(req.params.id,{min:1,name:'product_id'})))));
 }
 if(enabled('identity')){
  router.post('/api/auth/login',asyncRoute(async(req,res)=>res.json(await identity.login(req.body?.email,req.body?.password,req.ip))));
  router.get('/api/account/me',auth,(req,res)=>res.json(identity.me(req.user)));
 }
 if(enabled('admin')){
  router.get('/api/admin/products/count',auth,admin,asyncRoute(async(req,res)=>res.json(await catalog.count(validatePage(req.query,true),true))));
  router.get('/api/admin/products/categories',auth,admin,asyncRoute(async(req,res)=>res.json(await catalog.categories(true))));
  router.get('/api/admin/products/stats',auth,admin,asyncRoute(async(req,res)=>res.json(await catalog.stats())));
  router.get('/api/admin/products',auth,admin,asyncRoute(async(req,res)=>res.json(await catalog.page(validatePage(req.query,true),true))));
  router.get('/api/admin/products/:id',auth,admin,asyncRoute(async(req,res)=>res.json(await catalog.detail(requireInteger(req.params.id,{min:1}),true))));
  router.post('/api/admin/products',auth,admin,asyncRoute(async(req,res)=>res.status(201).json(await catalog.create(productInput(req.body)))));
  router.put('/api/admin/products/:id',auth,admin,asyncRoute(async(req,res)=>res.json(await catalog.update(requireInteger(req.params.id,{min:1}),productInput(req.body)))));
  router.delete('/api/admin/products/:id',auth,admin,asyncRoute(async(req,res)=>res.json(await catalog.delete(requireInteger(req.params.id,{min:1})))));
 }
 if(enabled('commerce')){
  router.get('/api/payment-return/:outcome',asyncRoute(async(req,res)=>{const result=paymentReturnPage(req.params.outcome,req.query.session_id);res.set(result.headers).type('html').send(result.html);}));
  router.get('/api/stripe-checkout/return/session/:sessionId',auth,asyncRoute(async(req,res)=>res.json(await stripeCheckout.orderForSession(req.user,req.params.sessionId))));
  const stripeWrites=(req,res,next)=>process.env.STRIPE_NODE_WRITES_ENABLED==='true'?next():res.status(503).json({detail:'Node Stripe writes disabled pending integration validation'});
  router.post('/api/stripe-checkout/sessions',auth,stripeWrites,asyncRoute(async(req,res)=>res.status(201).json(await stripeCheckout.create(req.user,req.headers['idempotency-key'],req.body))));
  router.get('/api/stripe-checkout/orders/:id',auth,asyncRoute(async(req,res)=>res.json(await stripeCheckout.status(req.user,requireInteger(req.params.id,{min:1})))));
  router.post('/api/stripe-checkout/orders/:id/cancel',auth,stripeWrites,asyncRoute(async(req,res)=>res.json(await stripeCheckout.cancel(req.user,requireInteger(req.params.id,{min:1})))));
  router.post('/api/stripe-checkout/orders/:id/reconcile',auth,stripeWrites,asyncRoute(async(req,res)=>res.json(await stripeCheckout.reconcile(req.user,requireInteger(req.params.id,{min:1})))));
  router.get('/api/stripe-checkout/orders/:id/resume',auth,asyncRoute(async(req,res)=>res.json(await stripeCheckout.resume(req.user,requireInteger(req.params.id,{min:1})))));
  router.post('/api/purchases',auth,asyncRoute(async(req,res)=>res.status(201).json(await orders.buy(req.user,req.headers['idempotency-key'],req.body))));
  router.post('/api/checkout',auth,asyncRoute(async(req,res)=>res.status(201).json(await orders.checkout(req.user,req.headers['idempotency-key'],req.body))));
  router.get('/api/orders/my',auth,asyncRoute(async(req,res)=>res.json(await orders.myOrders(req.user))));
  router.get('/api/orders/my/details',auth,asyncRoute(async(req,res)=>res.json(await orders.details(req.user))));
 }

 return router;
}
