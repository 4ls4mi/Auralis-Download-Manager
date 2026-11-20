// Real Windows executable: isolated profile and data, no native-host registration.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {mkdir,mkdtemp,readFile,rm} from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
const {chromium}=createRequire(import.meta.url)('../../glass-ui/node_modules/playwright-core');
assert.equal(process.platform,'win32');
const exe=process.env.AURALIS_EMBEDDED_EXE;assert.ok(exe,'AURALIS_EMBEDDED_EXE is required');
// The runner may be installed in System32, where WebView's sandbox cannot write.
const testBase=path.join(process.env.LOCALAPPDATA||os.tmpdir(),'AuralisRunner','smoke');
await mkdir(testBase,{recursive:true});
const root=await mkdtemp(path.join(testBase,'auralis-integrated-'));
const data=path.join(root,'data'),wait=ms=>new Promise(r=>setTimeout(r,ms));
const until=async(fn,msg,ms=90000)=>{const end=Date.now()+ms;let last;while(Date.now()<end){try{const v=await fn();if(v)return v}catch(e){if(e.fatal)throw e;last=e}await wait(250)}throw Error(msg+(last?': '+last.message:''))};
const contents=Buffer.alloc(1024*1024,0x41),hash=createHash('sha256').update(contents).digest('hex');
const server=createServer((req,res)=>{const m=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range||'');const start=m?Number(m[1]):0,end=m&&m[2]?Math.min(Number(m[2]),contents.length-1):contents.length-1;if(start>=contents.length){res.writeHead(416,{'Content-Range':`bytes */${contents.length}`});return res.end()}res.writeHead(m?206:200,{'Content-Type':'application/octet-stream','Content-Length':end-start+1,'Accept-Ranges':'bytes',...(m?{'Content-Range':`bytes ${start}-${end}/${contents.length}`}:{})});res.end(req.method==='HEAD'?undefined:contents.subarray(start,end+1))});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const probe=net.createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
async function ipc(command){const endpoint=JSON.parse(await readFile(path.join(data,'ipc.json'),'utf8'));return new Promise((resolve,reject)=>{let text='';const s=net.connect({host:'127.0.0.1',port:endpoint.port},()=>s.write(JSON.stringify({token:endpoint.token,...command})+'\n'));s.setTimeout(10000,()=>s.destroy(Error('IPC timeout')));s.on('data',b=>{text+=b;if(text.includes('\n')){s.end();resolve(text.trim())}});s.on('end',()=>resolve(text.trim()));s.on('error',reject)})}
async function browserCapture(url) {
 const host=process.env.AURALIS_NATIVE_HOST;assert.ok(host,'AURALIS_NATIVE_HOST is required');
 const message={url,filename:'from-browser.bin',size:contents.length,mime:'application/octet-stream',referrer:url,pageUrl:url,explicit:true,v:'0.2.4'};
 const body=Buffer.from(JSON.stringify(message)),header=Buffer.alloc(4);header.writeUInt32LE(body.length);
 return new Promise((resolve,reject)=>{
  const child=spawn(host,['glass-test.firefox.json','integration@misterdownloadmanager.com'],{env:{...process.env,MDM_DATA_DIR:data},stdio:['pipe','pipe','pipe']});
  let bytes=Buffer.alloc(0),errors='';const timer=setTimeout(()=>{child.kill();reject(Error('Browser helper timed out'))},30000);
  child.on('error',e=>{clearTimeout(timer);reject(e)});child.stderr.on('data',b=>errors+=b);
  child.on('exit',code=>{if(bytes.length<4){clearTimeout(timer);reject(Error(`Browser helper exited ${code}: ${errors}`))}});
  child.stdout.on('data',b=>{bytes=Buffer.concat([bytes,b]);if(bytes.length>=4&&bytes.length>=4+bytes.readUInt32LE(0)){clearTimeout(timer);child.stdin.end();try{resolve(JSON.parse(bytes.subarray(4,4+bytes.readUInt32LE(0))))}catch(e){reject(e)}}});
  child.stdin.write(Buffer.concat([header,body]));
 });
}
let app,browser,output='';
const spawnApp=()=>{
 const child=spawn(exe,[],{env:{...process.env,MDM_DATA_DIR:data,AURALIS_TEST_SKIP_HOST:'1',AURALIS_TEST_PANIC_LOG:path.join(root,'panic.txt'),RUST_BACKTRACE:'1',GLASS_TEST_CDP_PORT:String(port),WEBVIEW2_USER_DATA_FOLDER:path.join(root,'webview')},stdio:['ignore','pipe','pipe']});
 for(const stream of [child.stdout,child.stderr])stream.on('data',chunk=>{output=(output+chunk.toString()).slice(-12000)});
 return child;
};
const exited=message=>Object.assign(Error(message),{fatal:true});
try {
 app=spawnApp();
 browser=await until(async()=>{if(app.exitCode!==null)throw exited(`Auralis exited: ${app.exitCode}`);try{return await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:2000})}catch{return null}},'WebView did not start');
 const page=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&!p.url().includes('?')),'Main window missing');
 const identity=await until(async()=>JSON.parse(await ipc({query:'glass-backend'})),'Downloader did not start');assert.equal(identity.headless,true);assert.equal(identity.glass,true);
 const ps=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',`Get-CimInstance Win32_Process -Filter 'ParentProcessId=${app.pid}' | Select-Object -ExpandProperty Name`],{encoding:'utf8',timeout:15000});assert.equal(ps.status,0,'Could not inspect child processes');assert.doesNotMatch(ps.stdout,/^mdm-legacy\.exe\s*$/im,'A legacy downloader process was launched');
 await ipc({url:`http://127.0.0.1:${server.address().port}/embedded-smoke.bin`,dir:root,name:'embedded-smoke.bin',silent:true});
 const completed=await until(async()=>JSON.parse(await ipc({query:'list'})).downloads.find(d=>d.file==='embedded-smoke.bin'&&d.status==='Complete'),'Fixture download did not finish',120000);
 assert.equal(createHash('sha256').update(await readFile(completed.path)).digest('hex'),hash,'Downloaded file does not match');
 const browserUrl=`http://127.0.0.1:${server.address().port}/from-browser.bin`;
 const reply=await browserCapture(browserUrl);assert.equal(reply.ok,true,'Browser helper did not accept capture');
 await until(async()=>{const view=JSON.parse(await ipc({query:'glass-file-info'}));return view.info&&JSON.stringify(view.info).includes(browserUrl)},'Browser capture did not reach the embedded downloader');
 await page.evaluate(()=>window.__TAURI_INTERNALS__.invoke('quit_glass')).catch(()=>{});
 await until(()=>app.exitCode!==null,'Auralis did not stop and save',45000);assert.equal(app.exitCode,0);
 await browser.close();browser=null;
 app=spawnApp();
 browser=await until(async()=>{if(app.exitCode!==null)throw exited(`Auralis exited after restart: ${app.exitCode}`);try{return await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:2000})}catch{return null}},'WebView did not restart');
 const restarted=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&!p.url().includes('?')),'Restarted main window missing');
 await until(async()=>JSON.parse(await ipc({query:'list'})).downloads.find(d=>d.file==='embedded-smoke.bin'&&d.status==='Complete'),'Download was not restored after restart');
 await restarted.evaluate(()=>window.__TAURI_INTERNALS__.invoke('quit_glass')).catch(()=>{});
 await until(()=>app.exitCode!==null,'Restarted Auralis did not stop',45000);assert.equal(app.exitCode,0);
 console.log('PASS: integrated downloader ran without a legacy child, downloaded a verified file, saved, and restored it after restart.');
} catch(error) {
 if(output)console.error('Auralis output:',output);
 const panic=await readFile(path.join(root,'panic.txt'),'utf8').catch(()=>null);
 if(panic)console.error('Auralis panic:',panic.slice(-12000));
 throw error;
} finally {
 if(browser)await browser.close().catch(()=>{});
 if(app&&app.exitCode===null)app.kill();
 await new Promise(r=>server.close(r));
 await rm(root,{recursive:true,force:true,maxRetries:5,retryDelay:500}).catch(()=>{});
}
