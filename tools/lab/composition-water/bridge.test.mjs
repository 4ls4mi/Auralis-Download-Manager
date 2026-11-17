import {test} from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {queryEngine,readLive} from './bridge.mjs';

test('read-only bridge selects the real response and authenticates without exposing the token',async()=>{
 const token='fixture-local-token';const commands=[];
 const server=net.createServer(socket=>{let text='';socket.on('data',chunk=>{text+=chunk;const e=text.indexOf('\n');if(e<0)return;const msg=JSON.parse(text.slice(0,e));commands.push(msg);assert.equal(msg.token,token);if(msg.query==='list')socket.end(JSON.stringify({downloads:[{id:7,file:'fixture.zip',downloaded:27,size:100,speed:3}]})+'\n');else socket.end(JSON.stringify({downloads:[{id:7,segments:[{start:0,cursor:27,end:100,worker:4}],connections:[{id:4,state:'Receiving'}]}]})+'\n');});});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const dir=await mkdtemp(path.join(os.tmpdir(),'mdm-bridge-'));
 try{await writeFile(path.join(dir,'ipc.json'),JSON.stringify({port:server.address().port,token}));const value=await readLive(dir,7);assert.equal(value.download.downloaded,27);assert.equal(value.visual.segments[0].worker,4);assert.equal(JSON.stringify(value).includes(token),false);assert.deepEqual(commands.map(c=>c.query).sort(),['glass-visuals','list']);assert.equal(await readLive(dir,8),null);await assert.rejects(()=>queryEngine(dir,'delete'));await assert.rejects(()=>readLive(dir,-1));}
 finally{server.close();await rm(dir,{recursive:true,force:true})}
});
