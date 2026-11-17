// Development-only, read-only bridge from the original authenticated MDM IPC
// to the standalone composition window. Never passes the IPC token to WebView2.
import {readFile} from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {pathToFileURL} from 'node:url';

export async function queryEngine(dataDir, query) {
 if (!['list','glass-visuals'].includes(query)) throw new Error('Unsupported read-only query');
 const endpoint=JSON.parse(await readFile(path.join(dataDir,'ipc.json'),'utf8'));
 if (!Number.isInteger(endpoint.port)||endpoint.port<1||endpoint.port>65535||typeof endpoint.token!=='string'||!endpoint.token) throw new Error('Invalid local engine endpoint');
 return await new Promise((resolve,reject)=>{
  let text='';const socket=net.connect({host:'127.0.0.1',port:endpoint.port},()=>socket.write(JSON.stringify({token:endpoint.token,query})+'\n'));
  socket.setTimeout(5000,()=>socket.destroy(new Error('Engine request timed out')));
  socket.on('data',chunk=>{text+=chunk.toString('utf8');if(text.length>1024*1024){socket.destroy(new Error('Engine response too large'));return}const pos=text.indexOf('\n');if(pos>=0){socket.end();try{const value=JSON.parse(text.slice(0,pos));if(value.error)throw new Error('Engine rejected telemetry query');resolve(value)}catch(e){reject(e)}}});
  socket.on('error',reject);socket.on('end',()=>{if(!text.includes('\n'))reject(new Error('Incomplete engine response'))});
 });
}
export async function readLive(dataDir,id){
 if(!Number.isSafeInteger(id)||id<0)throw new Error('Invalid download id');
 const [list,visuals]=await Promise.all([queryEngine(dataDir,'list'),queryEngine(dataDir,'glass-visuals')]);
 if(!Array.isArray(list.downloads)||!Array.isArray(visuals.downloads))throw new Error('Invalid engine telemetry');
 const download=list.downloads.find(d=>d.id===id),visual=visuals.downloads.find(v=>v.id===id);
 return download?{download,visual:visual??null}:null;
}
export function startLiveBridge({exe,dataDir,id,env=process.env,intervalMs=900}){
 if(!exe||!dataDir||!Number.isSafeInteger(id)||id<0)throw new Error('A lab executable, data directory and download id are required');
 const child=spawn(exe,['--live'],{env,stdio:['pipe','ignore','pipe']});let busy=false,closed=false;
 const tick=async()=>{if(busy||closed)return;busy=true;try{const result=await readLive(dataDir,id);if(result&&!closed&&!child.stdin.destroyed){const safe=JSON.stringify(result).replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');child.stdin.write(safe+'\n');}}catch(e){if(!closed)child.emit('telemetry-error',e)}finally{busy=false}};
 const timer=setInterval(()=>void tick(),intervalMs);child.on('exit',()=>{closed=true;clearInterval(timer)});child.stdin.on('error',()=>{});void tick();return child;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 const [exe,idText]=process.argv.slice(2);const id=Number(idText);const dataDir=process.env.MDM_DATA_DIR;
 try{const child=startLiveBridge({exe,dataDir,id});child.on('telemetry-error',e=>console.error('Telemetry unavailable:',e.message));child.on('error',e=>{console.error('Could not start composition lab:',e.message);process.exitCode=1});child.on('exit',code=>{process.exitCode=code??1});}
 catch(e){console.error(e.message);process.exitCode=1;}
}
