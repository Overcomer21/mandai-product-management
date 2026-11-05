import {fail} from '../shared/errors.js';
export class CatalogService {
 constructor(repository,cache=null){this.repo=repository;this.cache=cache;}
 async categories(admin=false){return admin?this.repo.categories(true):this.cached('categories',()=>this.repo.categories(false));}
 async count(f,admin=false){const get=async()=>({total:await this.repo.count(f,admin)});return admin?get():this.cached('count:'+JSON.stringify(f),get);}
 async page(f,admin=false){return admin?this.repo.page(f,true):this.cached('page:'+JSON.stringify(f),()=>this.repo.page(f,false));}
 async detail(id,admin=false){const p=admin?await this.repo.detail(id,true):await this.cached('detail:'+id,()=>this.repo.detail(id,false));if(!p)fail(404,'Product not found');return p;}
 async stats(){return this.repo.stats()}
 async create(p){const r=await this.repo.create(p);await this.invalidate();return r;}
 async update(id,p){const r=await this.repo.update(id,p);await this.invalidate();return r;}
 async delete(id){const r=await this.repo.delete(id);await this.invalidate();return r;}
 async cached(key,loader){return this.cache?this.cache.getOrLoad(key,loader):loader();}
 async invalidate(){await this.cache?.invalidate();}
}
