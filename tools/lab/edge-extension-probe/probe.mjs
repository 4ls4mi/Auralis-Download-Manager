// Runs only on an isolated Windows CI profile; never touches a user's browser profile.
import {spawn} from 'node:child_process';
import {mkdtemp,writeFile,mkdir,rm} from 'node:fs/promises';
import os from 'node:os';import path from 'node:path';import assert from 'node:assert/strict';
const root=await mkdtemp(path.join(os.tmpdir(),'auralis-edge-probe-'));const profile=path.join(root,'profile'),extension=path.join(root,'extension');await mkdir(extension,{recursive:true});
await writeFile(path.join(extension,'manifest.json'),JSON.stringify({manifest_version:3,name:'Auralis isolated install probe',version:'1.0.0'}));
const executable=process.env.EDGE_PROBE_EXECUTABLE||path.join(process.env['PROGRAMFILES(X86)'],'Microsoft','Edge','Application','msedge.exe');
let processHandle;
function connect(){
 processHandle=spawn(executable,[`--user-data-dir=${profile}`,'--remote-debugging-pipe','--enable-unsafe-extension-debugging','--no-first-run','--no-default-browser-check','about:blank'],{stdio:['ignore','ignore','pipe','pipe','pipe']});
 let buffer='',id=0;const pending=new Map();processHandle.stdio[4].on('data',chunk=>{buffer+=chunk.toString();let split;while((split=buffer.indexOf('\0'))>=0){const raw=buffer.slice(0,split);buffer=buffer.slice(split+1);let msg;try{msg=JSON.parse(raw)}catch{continue}const entry=pending.get(msg.id);if(entry){pending.delete(msg.id);clearTimeout(entry.timer);msg.error?entry.reject(Error(msg.error.message)):entry.resolve(msg.result)}}});
 processHandle.on('exit',code=>{for(const item of pending.values()){clearTimeout(item.timer);item.reject(Error(`Edge exited with ${code}`))}pending.clear()});
 return (method,params={})=>new Promise((resolve,reject)=>{const n=++id,timer=setTimeout(()=>{pending.delete(n);reject(Error(`${method} timed out`))},30000);pending.set(n,{resolve,reject,timer});processHandle.stdio[3].write(JSON.stringify({id:n,method,params})+'\0')});
}
try{
 let send=connect();await send('Browser.getVersion');const loaded=await send('Extensions.loadUnpacked',{path:extension});assert.ok(loaded.id,'No extension ID returned');console.log('Loaded unpacked extension in isolated profile');
 const list=await send('Extensions.getExtensions');assert.ok(list.extensions.some(x=>x.id===loaded.id),'Extension absent immediately after loading');await send('Browser.close').catch(()=>{});await new Promise(r=>processHandle.once('exit',r));
 send=connect();await send('Browser.getVersion');const after=await send('Extensions.getExtensions');assert.ok(after.extensions.some(x=>x.id===loaded.id),'Unpacked extension did not persist after browser restart');console.log('PASS: extension remained installed in isolated profile after restart');await send('Browser.close').catch(()=>{});
}catch(e){console.error('PROBE FAILED:',e.message);process.exitCode=1;}finally{if(processHandle&&!processHandle.killed)processHandle.kill();await rm(root,{recursive:true,force:true,maxRetries:5,retryDelay:500}).catch(()=>{})}
