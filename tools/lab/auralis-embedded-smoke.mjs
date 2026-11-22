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
const slowContents=Buffer.alloc(32*1024*1024,0x62),slowHash=createHash('sha256').update(slowContents).digest('hex');
let requestCount=0,lastStatus=[],addResponse='';
const server=createServer((req,res)=>{
 requestCount++;
 const slow=req.url.startsWith('/resume-'),bytes=slow?slowContents:contents;
 const m=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range||'');
 const start=m?Number(m[1]):0,end=m&&m[2]?Math.min(Number(m[2]),bytes.length-1):bytes.length-1;
 if(start>=bytes.length){res.writeHead(416,{'Content-Range':`bytes */${bytes.length}`});return res.end()}
 res.writeHead(m?206:200,{'Content-Type':'application/octet-stream','Content-Length':end-start+1,'Accept-Ranges':'bytes',...(m?{'Content-Range':`bytes ${start}-${end}/${bytes.length}`}:{})});
 if(req.method==='HEAD')return res.end();
 if(!slow)return res.end(bytes.subarray(start,end+1));
 let offset=start;const timer=setInterval(()=>{if(offset>end){clearInterval(timer);return res.end()}const next=Math.min(offset+32768,end+1);res.write(bytes.subarray(offset,next));offset=next},50);
 res.on('close',()=>clearInterval(timer));
});
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
 const child=spawn(exe,[],{env:{...process.env,MDM_DATA_DIR:data,MDM_DOWNLOADS:root,AURALIS_TEST_SKIP_HOST:'1',AURALIS_TEST_PANIC_LOG:path.join(root,'panic.txt'),RUST_BACKTRACE:'1',GLASS_TEST_CDP_PORT:String(port),WEBVIEW2_USER_DATA_FOLDER:path.join(root,'webview')},stdio:['ignore','pipe','pipe']});
 for(const stream of [child.stdout,child.stderr])stream.on('data',chunk=>{output=(output+chunk.toString()).slice(-12000)});
 return child;
};
const exited=message=>Object.assign(Error(message),{fatal:true});
// A WebView can be recreated while Windows restores it. Retry only if the
// target disappeared; real shutdown errors still fail the integration test.
async function quitApp(preferred,label){
 let page=preferred,lastError='';
 for(let attempt=0;attempt<3&&app.exitCode===null;attempt++){
  if(!page||page.isClosed()){
   // WebView2 may replace its DevTools connection after a restart. A stale
   // Playwright connection can have no pages even while the new process is alive.
   // Reconnect to the same local endpoint. Any Auralis WebView may issue
   // quit_glass, including a completion window left open after the transfer.
   const appPage=connection=>connection.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&(/^(?:https?:\/\/tauri\.localhost|tauri:\/\/localhost)(?:[\/?#]|$)/i).test(p.url()));
   let lastReconnect=0;
   const next=await until(async()=>{
    if(app.exitCode!==null)return 'exited';
    let found=appPage(browser);
    if(found)return found;
    if(Date.now()-lastReconnect<1000)return null;
    lastReconnect=Date.now();
    try{
     const fresh=await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:1500});
     found=appPage(fresh);
     if(found){browser=fresh;return found}
     await fresh.close().catch(()=>{});
    }catch{/* Keep waiting for the replacement DevTools endpoint. */}
    return null;
   },`${label}: no Auralis window for shutdown`,20000);
   if(next==='exited')break;page=next;
  }
  try{await page.evaluate(()=>window.__TAURI_INTERNALS__.invoke('quit_glass'));break}
  catch(error){lastError=String(error);if(app.exitCode!==null)break;if(!/closed|destroyed|navigation|context/i.test(lastError))throw Error(`${label}: shutdown command failed: ${lastError}`);page=null;await wait(500)}
 }
 await until(()=>app.exitCode!==null,`${label} did not stop${lastError?`: ${lastError}`:''}`,45000);
 assert.equal(app.exitCode,0,`${label} exited unsuccessfully`);
}
try {
 app=spawnApp();
 browser=await until(async()=>{if(app.exitCode!==null)throw exited(`Auralis exited: ${app.exitCode}`);try{return await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:2000})}catch{return null}},'WebView did not start');
 const page=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&!p.url().includes('?')),'Main window missing');
 const identity=await until(async()=>JSON.parse(await ipc({query:'glass-backend'})),'Downloader did not start');assert.equal(identity.headless,true);assert.equal(identity.glass,true);
 // Verify the actual Windows title-bar control, not just the WebView rendering.
 const maximize=page.getByRole('button',{name:'Maximize or restore'});
 await maximize.click();
 await until(()=>page.evaluate(()=>window.__TAURI_INTERNALS__.invoke('plugin:window|is_maximized',{label:'main'})),'Maximize button did not maximize the window');
 await maximize.click();
 await until(async()=>!(await page.evaluate(()=>window.__TAURI_INTERNALS__.invoke('plugin:window|is_maximized',{label:'main'}))),'Maximize button did not restore the window');
 // Check the installed app's native region without capturing the runner's desktop.
 await page.evaluate(()=>{
  localStorage.setItem('mh-glass-material','builtin-aurora-night');
  localStorage.setItem('mh-glass-back-main','desktop');
  window.dispatchEvent(new Event('storage'));
 });
 const acrylicFrame=page.locator('.cg-native-backdrop.cg-material-builtin-aurora-night:not(.cg-maximized, .cg-tiled) .cg-content');
 await acrylicFrame.waitFor();
 const frameStyle=await acrylicFrame.evaluate(element=>{
  const style=getComputedStyle(element);
  return {inset:style.inset,radius:style.borderTopLeftRadius};
 });
 assert.equal(frameStyle.inset,'0px');
 assert.equal(frameStyle.radius,'20px');
 await until(async()=>{
  const frame=await page.evaluate(async()=>({
   region:await window.__TAURI_INTERNALS__.invoke('inspect_material_window_region'),
   notice:document.querySelector('.cg-window-notice')?.textContent,
  }));
  assert.ok(frame.region.rounded,JSON.stringify(frame));
  return true;
 },'The installed app did not apply a rounded native acrylic region',10000);
 const ps=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',`Get-CimInstance Win32_Process -Filter 'ParentProcessId=${app.pid}' | Select-Object -ExpandProperty Name`],{encoding:'utf8',timeout:15000});assert.equal(ps.status,0,'Could not inspect child processes');assert.doesNotMatch(ps.stdout,/^mdm-legacy\.exe\s*$/im,'A legacy downloader process was launched');
 const downloadUrl=`http://127.0.0.1:${server.address().port}/embedded-smoke-${Date.now()}.bin`;
 addResponse=await ipc({url:downloadUrl,silent:true});
 const completed=await until(async()=>{lastStatus=JSON.parse(await ipc({query:'list'})).downloads.map(({file,url,status,downloaded,error})=>({file,url,status,downloaded,error}));const item=lastStatus.find(d=>d.url===downloadUrl);if(item?.status==='Error')throw exited(`Fixture download failed: ${item.error||'unknown error'}`);if(item?.status==='Complete')return JSON.parse(await ipc({query:'list'})).downloads.find(d=>d.url===downloadUrl);return null},'Fixture download did not finish',120000);
 assert.ok(!path.relative(root,completed.path).startsWith('..')&&!path.isAbsolute(path.relative(root,completed.path)),'Test download escaped its isolated folder');
 assert.equal(createHash('sha256').update(await readFile(completed.path)).digest('hex'),hash,'Downloaded file does not match');
 const browserUrl=`http://127.0.0.1:${server.address().port}/from-browser.bin`;
 const reply=await browserCapture(browserUrl);assert.equal(reply.ok,true,'Browser helper did not accept capture');
 await until(async()=>{const view=JSON.parse(await ipc({query:'glass-file-info'}));return view.info&&JSON.stringify(view.info).includes(browserUrl)},'Browser capture did not reach the embedded downloader');
 // Exercise partial-download state across a full application restart.
 const resumeUrl=`http://127.0.0.1:${server.address().port}/resume-${Date.now()}.bin`;
 await ipc({url:resumeUrl,silent:true});
 const partial=await until(async()=>JSON.parse(await ipc({query:'list'})).downloads.find(d=>d.url===resumeUrl&&d.status==='Downloading'&&d.downloaded>65536),'Resume fixture did not start');
 await ipc({action:'pause',ids:[partial.id]});
 const paused=await until(async()=>JSON.parse(await ipc({query:'list'})).downloads.find(d=>d.id===partial.id&&d.status==='Stopped'&&d.downloaded>0),'Resume fixture did not pause');
 assert.ok(paused.downloaded<slowContents.length,'Resume fixture finished before it could be paused');
 await quitApp(page,'Auralis');
 await browser.close();browser=null;
 app=spawnApp();
 browser=await until(async()=>{if(app.exitCode!==null)throw exited(`Auralis exited after restart: ${app.exitCode}`);try{return await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:2000})}catch{return null}},'WebView did not restart');
 const restarted=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&!p.url().includes('?')),'Restarted main window missing');
 await until(async()=>JSON.parse(await ipc({query:'list'})).downloads.find(d=>d.url===downloadUrl&&d.status==='Complete'),'Download was not restored after restart');
 const restored=await until(async()=>JSON.parse(await ipc({query:'list'})).downloads.find(d=>d.url===resumeUrl&&d.status==='Stopped'&&d.downloaded>0),'Partial download was not restored');
 await ipc({action:'start',ids:[restored.id]});
 const resumed=await until(async()=>{const d=JSON.parse(await ipc({query:'list'})).downloads.find(d=>d.id===restored.id);if(d?.status==='Error')throw exited(`Resumed download failed: ${d.error||'unknown error'}`);return d?.status==='Complete'?d:null},'Partial download did not resume and finish',180000);
 assert.ok(!path.relative(root,resumed.path).startsWith('..')&&!path.isAbsolute(path.relative(root,resumed.path)),'Resumed download escaped its isolated folder');
 assert.equal(createHash('sha256').update(await readFile(resumed.path)).digest('hex'),slowHash,'Resumed file does not match');
 await quitApp(restarted,'Restarted Auralis');
 console.log('PASS: integrated downloader ran without a legacy child, downloaded a verified file, handled a browser capture, and resumed a partial download after restart.');
} catch(error) {
 console.error('Fixture diagnostics:',JSON.stringify({requestCount,lastStatus,gotAddResponse:Boolean(addResponse),appExit:app?.exitCode}));
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
