import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source=readFileSync(new URL('../../auralis-extension/cookie-export.js',import.meta.url),'utf8');
async function run({existing=false}={}){
 const calls=[],status={textContent:''},retry={hidden:false,addEventListener(){}};
 let tabUrl='https://www.youtube.com/',savedBlob;
 const youtube={name:'SID',value:'secret-value',domain:'.youtube.com',path:'/',secure:true,httpOnly:true,hostOnly:false,expirationDate:2000000000};
 const api={extension:{isAllowedIncognitoAccess:async()=>true},windows:{getAll:async()=>existing?[{incognito:true}]:[],create:async options=>{calls.push(['create',options]);return{id:2,tabs:[{id:3}]}},get:async()=>({tabs:[{id:3}]}),remove:async id=>calls.push(['remove',id])},tabs:{get:async()=>({url:tabUrl,status:'complete'}),update:async(_,value)=>{tabUrl=value.url;calls.push(['navigate',tabUrl])}},cookies:{getAll:async query=>{calls.push(['cookies',query]);return [youtube,{name:'other',value:'private',domain:'.other.com',path:'/'}]}}};
 const context={chrome:api,document:{getElementById:id=>id==='status'?status:retry,createElement:()=>({click(){calls.push(['save'])},remove(){}}),body:{append(){}}},Blob,URL:class extends URL{static createObjectURL(blob){savedBlob=blob;return 'blob:local'}static revokeObjectURL(){}},setTimeout:(fn)=>{queueMicrotask(fn);return 1},console};
 vm.runInNewContext(source,context);
 for(let i=0;i<50&&!status.textContent.includes('export started')&&!status.textContent.includes('Close existing');i++)await new Promise(r=>setImmediate(r));
 return {calls,status,savedBlob};
}
test('exports only YouTube private-store cookies and closes only the created private window',async()=>{
 const {calls,status,savedBlob}=await run();
 assert.match(status.textContent,/export started/);
 assert(calls.some(([a,q])=>a==='cookies'&&q.storeId==='1'));
 assert(calls.some(([a,q])=>a==='navigate'&&q==='https://www.youtube.com/robots.txt'));
 assert(calls.some(([a,id])=>a==='remove'&&id===2));
 const text=await savedBlob.text();assert.match(text,/#HttpOnly_\.youtube\.com\tTRUE\t\/\tTRUE\t2000000000\tSID\tsecret-value/);assert.doesNotMatch(text,/other\.com/);
});
test('does not open or close windows if an existing private window is present',async()=>{
 const {calls,status}=await run({existing:true});assert.match(status.textContent,/Close existing private windows/);assert.equal(calls.length,0);
});
