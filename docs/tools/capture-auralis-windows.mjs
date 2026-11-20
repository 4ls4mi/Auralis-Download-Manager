// Captures the real installed-build interface with isolated data and local transfers.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {mkdir,mkdtemp,readFile,rm} from 'node:fs/promises';
import net from 'node:net';import os from 'node:os';import path from 'node:path';
const require=createRequire(path.join(process.env.AURALIS_CAPTURE_TOOLS,'package.json'));
const {chromium}=require('playwright-core');
assert.equal(process.platform,'win32');
const exe=process.env.AURALIS_CAPTURE_EXE,output=process.env.AURALIS_CAPTURE_OUTPUT;assert.ok(exe&&output);
const base=path.join(process.env.LOCALAPPDATA||os.tmpdir(),'AuralisRunner','capture');await mkdir(base,{recursive:true});const root=await mkdtemp(path.join(base,'docs-'));const data=path.join(root,'data');await mkdir(output,{recursive:true});await mkdir(path.join(output,'frames'),{recursive:true});
const pause=ms=>new Promise(r=>setTimeout(r,ms));const until=async(fn,msg,ms=90000)=>{let last;const end=Date.now()+ms;while(Date.now()<end){try{const v=await fn();if(v)return v}catch(e){last=e}await pause(250)}throw Error(msg+(last?': '+last.message:''))};
const total=128*1024*1024,chunk=Buffer.alloc(128*1024,0x52);
const server=createServer((req,res)=>{
 const size=req.url.startsWith('/completed-')?1024*1024:total,m=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range||''),start=m?Number(m[1]):0,end=m&&m[2]?Math.min(Number(m[2]),size-1):size-1;
 if(start>=size){res.writeHead(416,{'Content-Range':`bytes */${size}`});return res.end()}
 res.writeHead(m?206:200,{'Content-Type':'application/octet-stream','Content-Length':end-start+1,'Accept-Ranges':'bytes',...(m?{'Content-Range':`bytes ${start}-${end}/${size}`}:{})});
 if(req.method==='HEAD')return res.end();
 let n=start;const started=Date.now();const timer=setInterval(()=>{if(n>end){clearInterval(timer);return res.end()}const phase=Math.floor((Date.now()-started)/2200)%5;const bytes=Math.min([8192,32768,16384,49152,24576][phase],end-n+1);res.write(chunk.subarray(0,bytes));n+=bytes},120);res.on('close',()=>clearInterval(timer));
});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const probe=net.createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
async function ipc(command){const endpoint=JSON.parse(await readFile(path.join(data,'ipc.json'),'utf8'));return new Promise((resolve,reject)=>{let text='';const socket=net.connect({host:'127.0.0.1',port:endpoint.port},()=>socket.write(JSON.stringify({token:endpoint.token,...command})+'\n'));socket.setTimeout(10000,()=>socket.destroy(Error('IPC timeout')));socket.on('data',b=>{text+=b;if(text.includes('\n')){socket.end();resolve(text.trim())}});socket.on('end',()=>resolve(text.trim()));socket.on('error',reject)})}
let app,browser;let outputLog='';
try{
 app=spawn(exe,[],{env:{...process.env,MDM_DATA_DIR:data,MDM_DOWNLOADS:root,AURALIS_TEST_SKIP_HOST:'1',GLASS_TEST_CDP_PORT:String(port),WEBVIEW2_USER_DATA_FOLDER:path.join(root,'webview')},stdio:['ignore','pipe','pipe']});for(const stream of [app.stdout,app.stderr])stream.on('data',b=>{outputLog=(outputLog+b).slice(-6000)});
 browser=await until(async()=>{if(app.exitCode!==null)throw Error(`Auralis exited: ${app.exitCode}`);try{return await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:2000})}catch{return null}},'WebView did not start');
 const pageFor=async(key)=>until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&p.url().includes(key)),`Window ${key} did not open`);
 let main=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&!p.url().includes('?')),'Main window missing');
 await until(async()=>JSON.parse(await ipc({query:'glass-backend'})).glass,'Downloader not ready');
 await main.evaluate(()=>{localStorage.setItem('mh-glass-material','frosted-water-351');localStorage.setItem('mh-glass-indicator','blue-purple');localStorage.setItem('mh-glass-connection-indicator','blue-purple');localStorage.setItem('mh-glass-graph-indicator','blue-purple');for(const k of ['progress-material','connection-material','graph-material'])localStorage.setItem('mh-glass-'+k,'liquid-glass');localStorage.setItem('auralis-browser-guide-seen','1')});await main.reload();await main.waitForSelector('.cg-toolbar');
 const invoke=(cmd,args={})=>main.evaluate(([c,a])=>window.__TAURI_INTERNALS__.invoke(c,a),[cmd,args]);
 // Use a wider real window so the download table fits without cropping columns.
 await invoke('plugin:window|set_size',{label:'main',value:{Logical:{width:1300,height:720}}});
 await until(async()=>main.evaluate(()=>{const table=document.querySelector('.cg-table-viewport');return table&&table.scrollWidth<=table.clientWidth+2}),'Main download columns do not fit in the capture window');
 const downloadUrl=`http://127.0.0.1:${server.address().port}/sample-archive.bin`;await ipc({url:downloadUrl,silent:true});
 const item=await until(async()=>JSON.parse(await ipc({query:'list'})).downloads.find(d=>d.url===downloadUrl&&d.status==='Downloading'),'Download did not start');
 await invoke('open_glass_window',{label:`download-${item.id}`,url:`/?detail=${item.id}`,width:880,height:600});const progress=await pageFor(`detail=${item.id}`);await progress.waitForSelector('.cg-mdm-details');
 // Accumulate real speed samples before capturing the graph.
 await pause(16000);await progress.screenshot({path:path.join(output,'download.png')});
 for(let i=0;i<24;i++){await progress.screenshot({path:path.join(output,'frames',`frame-${String(i).padStart(3,'0')}.png`)});await pause(125)}
 await invoke('open_glass_window',{label:'settings',url:'/?settings=1&tab=Appearance',width:1024,height:720});const settings=await pageFor('settings=1');await settings.getByRole('button',{name:'Indicators',exact:true}).click();await pause(500);await settings.screenshot({path:path.join(output,'settings.png')});
 const infoUrl=`http://127.0.0.1:${server.address().port}/new-file.bin`;await ipc({url:infoUrl,silent:false});const pending=await until(async()=>{const p=JSON.parse(await ipc({query:'glass-file-info'}));return p.info&&p.info.url===infoUrl?p:null},'File information unavailable');await invoke('open_glass_window',{label:`info-${pending.id}`,url:`/?request=${pending.id}`,width:850,height:580});const info=await pageFor(`request=${pending.id}`);await info.waitForSelector('.cg-file-info');await pause(500);await info.screenshot({path:path.join(output,'file-info.png')});
 const doneUrl=`http://127.0.0.1:${server.address().port}/completed-example.bin`;await ipc({url:doneUrl,silent:true});const done=await until(async()=>JSON.parse(await ipc({query:'list'})).downloads.find(d=>d.url===doneUrl&&d.status==='Complete'),'Completed fixture did not finish');await invoke('open_glass_window',{label:`complete-${done.id}`,url:`/?complete=${done.id}`,width:780,height:500});const complete=await pageFor(`complete=${done.id}`);await complete.waitForSelector('.cg-complete-page');await pause(300);await complete.screenshot({path:path.join(output,'complete.png')});
 await main.screenshot({path:path.join(output,'main.png')});
 for(const material of ['brushed-glass','rose-pine','window-glass','oversimplified','builtin-obsidian-matte','builtin-smoked-glass','builtin-pearl-frost']){
  await main.evaluate(value=>localStorage.setItem('mh-glass-material',value),material);
  await main.reload();await main.waitForSelector('.cg-toolbar');await pause(600);
  await main.screenshot({path:path.join(output,`material-${material}.png`)});
 }
 await main.evaluate(()=>localStorage.setItem('mh-glass-material','frosted-water-351'));
 await main.reload();await main.waitForSelector('.cg-toolbar');
 await invoke('plugin:window|maximize',{label:'main'});
 await until(async()=>main.evaluate(()=>document.querySelector('.cg-window')?.classList.contains('cg-maximized')),'Main window did not enter the maximized layout');
 await pause(1000);await main.screenshot({path:path.join(output,'main-maximized.png')});
 console.log('Captured the real Windows app with local downloads and measured speed samples.');
 await invoke('quit_glass').catch(()=>{});await until(()=>app.exitCode!==null,'Auralis did not exit',45000);
}catch(error){if(outputLog)console.error('Auralis output:',outputLog);throw error}
finally{if(browser)await browser.close().catch(()=>{});if(app&&app.exitCode===null)app.kill();server.closeAllConnections();await new Promise(r=>server.close(r));await rm(root,{recursive:true,force:true,maxRetries:5,retryDelay:500}).catch(()=>{})}
