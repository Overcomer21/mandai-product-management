import {createHash} from 'node:crypto';
// Mirrors Python json.dumps(value, sort_keys=True): sorted keys, comma-space and colon-space.
export function pythonJson(value){
 if(Array.isArray(value))return '['+value.map(pythonJson).join(', ')+']';
 if(value&&typeof value==='object')return '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+': '+pythonJson(value[k])).join(', ')+'}';
 return JSON.stringify(value);
}
export function fingerprint(value){return createHash('sha256').update(pythonJson(value)).digest('hex');}
