import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
test('a helper that does not identify Auralis clears the previously displayed app version',async()=>{
 const code=readFileSync(new URL('../../auralis-extension/background.js',import.meta.url),'utf8');
 const start=code.indexOf('let status = null;');
 const end=code.indexOf('// Whether this computer',start);
 assert.ok(start>=0&&end>start);
 const context={store:{status:{why:null,app:'0.3.48',engine:'0.5.2'}},Date};
 context.ext={storage:{local:{get:async()=>({status:context.store.status}),set:async value=>{context.store.status=value.status}}}};
 context.showStatus=async()=>{};context.syncOpenedRule=async()=>{};
 const invoke=runInNewContext(`(async()=>{${code.slice(start,end)}; await noteStatus(null,null,'0.5.2'); return await readStatus()})()`,context);
 const status=await invoke;
 assert.equal(status.app,null);assert.equal(status.engine,'0.5.2');
});
