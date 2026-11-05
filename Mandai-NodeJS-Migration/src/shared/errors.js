export class HttpError extends Error { constructor(status, detail) {super(detail);this.status=status;this.detail=detail;} }
export const fail=(status,detail)=>{throw new HttpError(status,detail)};
export const asyncRoute=fn=>(req,res,next)=>Promise.resolve(fn(req,res,next)).catch(next);
export function requireInteger(value,{name='value',min=0,max=Number.MAX_SAFE_INTEGER}={}) {
 const n=Number(value);if(!Number.isSafeInteger(n)||n<min||n>max)fail(422,`Invalid ${name}`);return n;
}
export function parseBoolean(value){return value===true||value==='true'||value==='1';}
export function validatePage(q,admin=false){
 const limit=(q.limit==null&&admin)?null:requireInteger(q.limit??20,{name:'limit',min:1,max:100});
 const offset=requireInteger(q.offset??0,{name:'offset'});
 const sort=q.sort??'Default';if(!['Default','Name','Price low','Price high'].includes(sort))fail(422,'Invalid sort');
 if(q.category&&String(q.category).length>100)fail(422,'Invalid category');
 if(q.search&&String(q.search).length>160)fail(422,'Invalid search');
 return {limit,offset,sort,category:q.category??null,search:q.search??null,inStock:parseBoolean(q.in_stock)};
}
export function productInput(p){
 if(!p||typeof p!=='object'||Array.isArray(p))fail(422,'Invalid product');
 const name=p.name,description=p.description??'',category=p.category??'Merchandise',price=Number(p.price),stock=Number(p.stock),image_url=p.image_url??'',spin_image_urls=p.spin_image_urls??'',is_active=p.is_active??true;
 if(typeof name!=='string'||name.length<1||name.length>160||typeof description!=='string'||description.length>1000||typeof category!=='string'||category.length>100||typeof image_url!=='string'||image_url.length>2048||typeof spin_image_urls!=='string'||!Number.isFinite(price)||price<0||Math.round(price*100)!==price*100||!Number.isSafeInteger(stock)||stock<0||typeof is_active!=='boolean')fail(422,'Invalid product fields');
 return {name,description,category,price,stock,is_active,image_url,spin_image_urls};
}
