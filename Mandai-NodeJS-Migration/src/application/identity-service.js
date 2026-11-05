import argon2 from 'argon2';
import jwt from 'jsonwebtoken';
import {fail} from '../shared/errors.js';
export class IdentityService{
 constructor(repository,guard=null){this.repo=repository;this.guard=guard;}
 async login(email,password,ip){if(typeof email!=='string'||typeof password!=='string')fail(422,'Invalid credentials');email=email.toLowerCase().trim();await this.guard?.check(email,ip);const u=await this.repo.byEmail(email);const valid=u?await argon2.verify(u.password_hash,password).catch(()=>false):false;if(!valid){await this.guard?.failure(email,ip);fail(401,'Invalid credentials')}await this.guard?.success(email,ip);const secret=process.env.JWT_SECRET;if(!secret||secret.length<32)fail(503,'Authentication service unavailable');return {access_token:jwt.sign({sub:String(u.id)},secret,{algorithm:'HS256',expiresIn:'4h'}),token_type:'bearer',role:u.role};}
 async authenticate(auth){if(!auth?.startsWith('Bearer '))fail(401,'Authentication required');let token;try{token=jwt.verify(auth.slice(7),process.env.JWT_SECRET,{algorithms:['HS256']});}catch{fail(401,'Invalid or expired token')}const user=await this.repo.byId(Number(token.sub));if(!user)fail(401,'Invalid or expired token');return user;}
 me(u){return {email:u.email,delivery_address:u.delivery_address,phone_number:u.phone_number,payment_method:u.payment_method};}
}
