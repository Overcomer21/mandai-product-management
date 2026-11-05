import {query,transaction} from './db.js';
import {fail} from '../shared/errors.js';
const columns='Id AS id, Name AS name, Description AS description, Category AS category, Price AS price, Stock AS stock, IsActive AS is_active, ImageUrl AS image_url, SpinImageUrls AS spin_image_urls';
export const productColumns=columns;
const map=p=>({...p,price:Number(p.price),is_active:!!p.is_active});
const escapeLike=s=>s.replace(/\\/g,'\\\\').replace(/%/g,'\\%').replace(/_/g,'\\_');
export function filterSql(f,admin=false){
 let where=admin?'WHERE 1=1':'WHERE IsActive=1';const params=[];
 if(f.category&&f.category!=='All'){where+=' AND Category=@p'+params.length;params.push(f.category);}
 if(f.search&&f.search.trim()){where+=` AND (LOWER(Name) LIKE @p${params.length} ESCAPE '\\' OR LOWER(Category) LIKE @p${params.length} ESCAPE '\\' OR LOWER(Description) LIKE @p${params.length} ESCAPE '\\')`;params.push('%'+escapeLike(f.search.trim().toLowerCase())+'%');}
 if(f.inStock)where+=' AND Stock>0';
 return {where,params};
}
export class SqlCatalogRepository {
 async categories(admin=false){const r=await query(`SELECT DISTINCT Category AS category FROM Products ${admin?'':'WHERE IsActive=1'} ORDER BY Category`);return r.recordset.map(x=>x.category);}
 async count(f,admin=false){const {where,params}=filterSql(f,admin),r=await query(`SELECT COUNT(*) AS total FROM Products ${where}`,params);return r.recordset[0].total;}
 async page(f,admin=false){const {where,params}=filterSql(f,admin);const order=({'Default':'Id','Name':'Name, Id','Price low':'Price ASC, Id','Price high':'Price DESC, Id'})[f.sort];
  let sql=`SELECT ${columns} FROM Products ${where} ORDER BY ${order}`;
  if(f.limit!==null){sql+=` OFFSET @p${params.length} ROWS FETCH NEXT @p${params.length+1} ROWS ONLY`;params.push(f.offset,f.limit);}
  return (await query(sql,params)).recordset.map(map);
 }
 async detail(id,admin=false){const r=await query(`SELECT ${columns} FROM Products WHERE Id=@p0${admin?'':' AND IsActive=1'}`,[id]);return r.recordset[0]?map(r.recordset[0]):null;}
 async stats(){const r=await query('SELECT COUNT(*) AS total, COALESCE(SUM(CASE WHEN IsActive=1 THEN 1 ELSE 0 END),0) AS active, COALESCE(SUM(Stock),0) AS stock FROM Products');return r.recordset[0];}
 async create(p){return transaction(async tx=>{const keys=['Name','Description','Category','Price','Stock','IsActive','ImageUrl','SpinImageUrls'],vals=Object.values(p);const r=await query(`INSERT INTO Products (${keys.join(',')}) OUTPUT INSERTED.Id AS id VALUES (${vals.map((_,i)=>'@p'+i).join(',')})`,vals,tx);const id=r.recordset[0].id;const d=await query(`SELECT ${columns} FROM Products WHERE Id=@p0`,[id],tx);return map(d.recordset[0]);});}
 async update(id,p){return transaction(async tx=>{const exists=await query('SELECT Id FROM Products WITH (UPDLOCK) WHERE Id=@p0',[id],tx);if(!exists.recordset.length)fail(404,'Product not found');const keys=['Name','Description','Category','Price','Stock','IsActive','ImageUrl','SpinImageUrls'],vals=Object.values(p);await query(`UPDATE Products SET ${keys.map((k,i)=>k+'=@p'+i).join(',')} WHERE Id=@p${vals.length}`,[...vals,id],tx);const r=await query(`SELECT ${columns} FROM Products WHERE Id=@p0`,[id],tx);return map(r.recordset[0]);});}
 async delete(id){try{const r=await query('DELETE FROM Products WHERE Id=@p0',[id]);if(!r.rowsAffected[0])fail(404,'Product not found');return {deleted:true,deactivated:false,action:'deleted'};}catch(e){if(e.number===547||e.originalError?.info?.number===547)fail(409,'Unable to delete product. This product has existing transactions or related records and cannot be deleted.');throw e;}}
}
