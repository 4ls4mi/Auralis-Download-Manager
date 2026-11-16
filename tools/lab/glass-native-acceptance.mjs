// Real Windows x64 shell + original native browser host + original engine.
// No mock Tauri commands or fake transfer telemetry are used in this acceptance run.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import net from 'node:net';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {mkdir,readFile,writeFile,access} from 'node:fs/promises';
import path from 'node:path';
const require=createRequire(import.meta.url);
const {chromium}=require('../../glass-ui/node_modules/playwright-core');
assert.equal(process.platform,'win32','Run native acceptance only on Windows x64.');
assert.equal(process.arch,'x64');
const folder=process.env.GLASS_E2E_DIR;
assert(folder&&process.env.GLASS_E2E_EXE,'Set the isolated test directory and executable.');
const output=path.join(folder,'proof');await mkdir(output,{recursive:true});
const data=path.join(folder,'data');await mkdir(data,{recursive:true});
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const until=async(fn,message,timeout=45000)=>{const start=Date.now();let last;while(Date.now()-start<timeout){try{const value=await fn();if(value)return value;}catch(e){last=e;}await wait(180);}throw new Error(message+(last?': '+last.message:''));};
const results=[];
const passed=name=>{results.push({name,status:'passed'});console.log('PASS: '+name);};
let headersPreserved=0,browser,shell;
let shellError='',shellExit=null;
const size=16*1024*1024;
const block=Buffer.alloc(64*1024,0x47);
const expectedHash=createHash('sha256');for(let n=0;n<size;n+=block.length)expectedHash.update(block);const expected=expectedHash.digest('hex');
const server=createServer((req,res)=>{
 if(req.headers.cookie!=='glass_acceptance=1'||!req.headers.referer||!req.headers['user-agent']?.includes('Firefox/')){res.writeHead(403);res.end('Missing original browser request context');return;}
 headersPreserved++;
 const range=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range||'');
 const total=req.url.includes('thirty-two')?64*1024*1024:size;
 const start=range?Number(range[1]):0,end=range&&range[2]?Math.min(total-1,Number(range[2])):total-1;
 if(start>=total||end<start){res.writeHead(416,{'Content-Range':`bytes */${total}`});res.end();return;}
 res.writeHead(range?206:200,{'Content-Type':'application/zip','Content-Length':end-start+1,'Accept-Ranges':'bytes','ETag':'"glass-native-fixture-v1"','Content-Disposition':'attachment; filename="fixture.zip"',...(range?{'Content-Range':`bytes ${start}-${end}/${total}`}:{})});
 if(req.method==='HEAD'){res.end();return;}
 let at=start;
 const tick=setInterval(()=>{if(at>end){clearInterval(tick);res.end();return;}const bytes=Math.min(block.length,end-at+1);res.write(block.subarray(0,bytes));at+=bytes;},90);
 res.on('close',()=>clearInterval(tick));
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const address=`http://127.0.0.1:${server.address().port}`;
const portServer=net.createServer();await new Promise(r=>portServer.listen(0,'127.0.0.1',r));const port=portServer.address().port;await new Promise(r=>portServer.close(r));
async function ipc(command){const endpoint=JSON.parse(await readFile(path.join(data,'ipc.json'),'utf8'));return new Promise((resolve,reject)=>{let text='';const socket=net.connect({host:'127.0.0.1',port:endpoint.port},()=>socket.write(JSON.stringify({token:endpoint.token,...command})+'\n'));socket.setTimeout(10000,()=>socket.destroy(new Error('IPC timeout')));socket.on('data',b=>{text+=b.toString();if(text.includes('\n')){socket.end();try{resolve(JSON.parse(text.split('\n')[0]));}catch(e){reject(e)}}});socket.on('error',reject);});}
async function capture(name){
 const host=path.join(path.dirname(process.env.GLASS_E2E_EXE),'misterdownloadmanager-nmhost.exe');
 const message={url:address+'/'+name,filename:name,size:name.includes('thirty-two')?64*1024*1024:size,mime:'application/zip',referrer:address+'/source',pageUrl:address+'/source',cookies:'glass_acceptance=1',userAgent:'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:144.0) Gecko/20100101 Firefox/144.0',explicit:true,v:'0.2.4'};
 const bytes=Buffer.from(JSON.stringify(message));const header=Buffer.alloc(4);header.writeUInt32LE(bytes.length);
 const hostReply=await new Promise((resolve,reject)=>{const child=spawn(host,[],{env:{...process.env,MDM_DATA_DIR:data},stdio:['pipe','pipe','pipe']});let raw=Buffer.alloc(0);const timer=setTimeout(()=>{child.kill();reject(new Error('Native browser host did not reply'));},30000);child.on('error',reject);child.stdout.on('data',b=>{raw=Buffer.concat([raw,b]);if(raw.length>=4&&raw.length>=4+raw.readUInt32LE(0)){clearTimeout(timer);child.stdin.end();resolve(JSON.parse(raw.subarray(4,4+raw.readUInt32LE(0)).toString()));}});child.stdin.write(Buffer.concat([header,bytes]));});
 assert.equal(hostReply.ok,true,'Original native messaging host accepted capture');
 return message;
}
async function pageFor(key){return until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&p.url().includes(key)),'Native window did not open: '+key);}
const invoke=(page,command,args={})=>Promise.race([page.evaluate(([command,args])=>window.__TAURI_INTERNALS__.invoke(command,args),[command,args]),wait(12000).then(()=>{throw new Error('Native command timed out: '+command)})]);
async function screenshot(page,name){await page.screenshot({path:path.join(output,name+'.png'),timeout:7000});}
async function assertFits(page,name){
 await until(async()=>{
  const overflow=await page.evaluate(()=>{const frame=document.querySelector('.cg-content')?.getBoundingClientRect(),fit=document.querySelector('.cg-fit-content')?.getBoundingClientRect();const out=Array.from(document.querySelectorAll('.cg-fit-content,.cg-page,.cg-settings-body,.cg-settings-nav,.cg-sidebar,.cg-toolbar,.cg-window-top')).filter(el=>el.clientWidth&&el.clientHeight&&(el.scrollHeight>el.clientHeight+3||el.scrollWidth>el.clientWidth+3)).map(el=>el.className);if(frame&&fit&&(fit.right>frame.right+3||fit.bottom>frame.bottom+3))out.push('window bounds');const root=document.querySelector('.cg-fit-content');const zoom=root?Number.parseFloat(getComputedStyle(root).zoom)||1:1;for(const el of document.querySelectorAll('.cg-toolbar button span,.cg-sidebar button span,.cg-mdm-details dt,.cg-mdm-details dd')){if(el.getBoundingClientRect().width>0&&Number.parseFloat(getComputedStyle(el).fontSize)*zoom<11.5)out.push('unreadable text');}return out});
  return overflow.length===0;
 },name+' has clipped content or would require page scrolling');
}
async function resizeWindow(page,label,width,height){await invoke(page,'plugin:window|set_size',{label,size:{type:'Logical',data:{width,height}}});await wait(450);}
async function setTheme(settings,light){await settings.getByRole('button',{name:'Appearance',exact:true}).click();await settings.getByRole('button',{name:light?'Light crystal':'Dark crystal',exact:true}).click();await wait(350);}
async function bothThemes(page,name,settings){for(const light of [false,true]){await setTheme(settings,light);await until(()=>page.locator(light?'.cg-light':'.cg-dark').count(),'Appearance did not reach '+name);await screenshot(page,name+(light?'-light':'-dark'));}}
try{
 shell=spawn(process.env.GLASS_E2E_EXE,[],{env:{...process.env,MDM_DATA_DIR:data,MDM_REMOTE:'off',GLASS_TEST_CDP_PORT:String(port),WEBVIEW2_USER_DATA_FOLDER:path.join(folder,'webview'),WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:`--remote-debugging-port=${port} --remote-debugging-address=127.0.0.1 --remote-allow-origins=*`},stdio:['ignore','pipe','pipe']});
 shell.stdout.on('data',b=>{shellError+=b.toString()});shell.stderr.on('data',b=>{shellError+=b.toString()});
 shell.on('error',e=>{shellError+=e.message;shellExit='spawn error'});shell.on('exit',(code,signal)=>{shellExit={code,signal}});
 browser=await until(async()=>{if(shellExit!==null)throw new Error('Glass exited before WebView2 started: '+JSON.stringify(shellExit)+' '+shellError);try{return await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:3000})}catch{return null}},'WebView2 CDP was not available',90000);
 const main=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.url().includes('?')),'Main native WebView did not appear');
 await main.waitForSelector('.cg-toolbar');await until(async()=>{const d=await ipc({query:'glass-backend'});return d.headless&&d.glass},'Original headless backend did not start',60000);
 passed('One Glass shell connects to the original headless MDM backend');
 await main.locator('.cg-toolbar').getByRole('button',{name:'Settings',exact:true}).click();const settings=await pageFor('settings=');
 await settings.getByRole('button',{name:'General',exact:true}).click();
 await settings.getByLabel('Show download complete dialog').uncheck();
 await until(async()=>!(await invoke(main,'glass_settings')).show_complete,'Turning completion off failed through the actual Tauri bridge');
 await settings.getByLabel('Show download complete dialog').check();
 await until(async()=>(await invoke(main,'glass_settings')).show_complete,'Turning completion on failed through the actual Tauri bridge');
 passed('Completion-dialog checkbox saves through the real native bridge');
 await capture('fixture-eight.zip');let info=await pageFor('request=');await info.waitForSelector('.cg-file-info');await wait(350);
 assert.equal((await ipc({query:'list'})).downloads.length,0,'Capture must wait for user confirmation');assert.equal((await ipc({query:'list'})).downloads.some(f=>f.status==='Downloading'),false,'Metadata probing must not create a running download before confirmation');
 await bothThemes(info,'file-info',settings);
 const destination=path.join(folder,'downloads','fixture-eight.zip');
 await info.getByLabel('Save As',{exact:true}).fill(destination);await info.getByLabel('Chunks / connections').selectOption('8');await info.getByRole('button',{name:'Start Download',exact:true}).click();
 const first=await until(async()=>{const d=await ipc({query:'list'});return d.downloads.find(f=>f.file==='fixture-eight.zip');},'Original engine did not add the chosen file');
 let progress=await pageFor('detail='+first.id);await progress.waitForSelector('.cg-mdm-details');
 await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.id===first.id)?.downloaded>0,'Original HTTP engine received no bytes');
 await progress.getByRole('button',{name:'Pause',exact:true}).click();await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.id===first.id)?.status==='Stopped','Transfer did not pause');
 assert.equal(progress.isClosed(),false,'Pausing in the progress window keeps it open');
 await progress.getByRole('button',{name:'Resume',exact:true}).click();
 await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.id===first.id)?.status==='Downloading','Transfer did not resume');
 await main.locator('.cg-row').first().click();await main.locator('.cg-toolbar').getByRole('button',{name:'Stop',exact:true}).click();
 await until(()=>progress.isClosed(),'Stopping from the main window did not close progress');await wait(1000);
 await main.locator('.cg-toolbar').getByRole('button',{name:'Resume',exact:true}).click();progress=await pageFor('detail='+first.id);
 await progress.getByRole('button',{name:'Pause',exact:true}).click();await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.id===first.id)?.status==='Stopped','Transfer did not pause again');
 passed('Pause keeps progress open; Stop from the main window closes it');
 assert.equal(await progress.locator('.cg-chunk-map>span').count(),8);await main.waitForSelector('.cg-row');assert.equal(await main.locator('.cg-row').first().locator('.cg-chunk-map>span').count(),8);
 assert.equal(await progress.locator('.cg-mdm-details dt').allTextContents().then(a=>a.join('|')),'Status|File size|Downloaded|Transfer rate|Time left|Resume capability|Server');
 assert(headersPreserved>0,'Captured cookie/referrer/User-Agent reached the original HTTP engine');
 passed('Original native host capture opens FileInfo before transfer and preserves browser context');
 passed('Chosen destination and eight independently measured chunks reach both windows');
 await bothThemes(progress,'progress',settings);await bothThemes(main,'main',settings);
 await progress.locator('.cg-connection-details>summary').click();await assertFits(progress,'Expanded connection details');await screenshot(progress,'progress-expanded-connections');
 await resizeWindow(progress,'download-'+first.id,620,500);await assertFits(progress,'Small progress window with expanded connections');await screenshot(progress,'progress-small-expanded');
 await progress.locator('.cg-connection-details>summary').click();await resizeWindow(progress,'download-'+first.id,880,680);
 await resizeWindow(main,'main',800,540);await assertFits(main,'Small main window');await screenshot(main,'main-small');await resizeWindow(main,'main',1480,850);
 passed('Main and expanded progress content fit resized native windows without page scrolling');
 await invoke(main,'update_glass_setting',{key:'max_connections',value:'32'});
 assert.equal((await invoke(main,'dashboard_visuals')).downloads.find(f=>f.id===first.id).chunk_count,8);
 passed('Changing the global connection setting preserves an existing file’s selected chunk count');
 await setTheme(settings,false);
 await progress.getByRole('button',{name:'Resume',exact:true}).click();
 // Main-window timers must not own completion lifecycle.
 await invoke(main,'plugin:window|hide',{label:'main'});
 const complete=await pageFor('complete='+first.id);await complete.waitForSelector('.cg-complete-page');
 assert.equal(await complete.getByTitle('Drag the file into a folder or an app').isEnabled(),true,'Completed file drag control should be available');assert.equal(await complete.getByTitle('Hide to tray').isVisible(),true,'Completed window must offer a tray control');
 await until(()=>progress.isClosed(),'Progress window did not close on completion');
 await invoke(main,'plugin:window|show',{label:'main'});
 await bothThemes(complete,'complete',settings);
 assert((await readFile(destination)).every(b=>b===0x47),'Original engine output matches the served bytes');
 passed('Actual transfer completes while main is hidden; progress closes and completion dialog opens');
 await invoke(main,'file_operation',{id:first.id,operation:'checksum',value:expected});
 const check=await until(async()=>{const r=await invoke(main,'file_operation',{id:first.id,operation:'checksum-result',value:null});return r.complete?r:null},'Original engine checksum verifier did not finish');assert.equal(check.matches,true);passed('Original engine verifies the completed file checksum');
 await complete.getByRole('button',{name:'Close',exact:true}).click();
 await capture('fixture-thirty-two.zip');info=await pageFor('request=');await info.waitForSelector('.cg-file-info');await info.getByLabel('Save As',{exact:true}).fill(path.join(folder,'downloads','fixture-thirty-two.zip'));await info.getByLabel('Chunks / connections').selectOption('32');await info.getByRole('button',{name:'Start Download',exact:true}).click();
 const second=await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.file==='fixture-thirty-two.zip'),'Second file missing');const progress32=await pageFor('detail='+second.id);await progress32.waitForSelector('.cg-chunk-map');await until(async()=>await progress32.locator('.cg-chunk-map>span').count()===32,'Progress did not show 32 selected chunks');await screenshot(progress32,'progress-32-chunks');
 const done32=await pageFor('complete='+second.id);await done32.waitForSelector('.cg-complete-page');await done32.getByRole('button',{name:'Close',exact:true}).click();
 const rows=main.locator('.cg-row');await until(async()=>await rows.count()===2,'Main list did not update');await rows.first().click({button:'right'});await main.waitForSelector('.cg-context');await bothThemes(main,'context-menu',settings);await main.keyboard.press('Escape');
 await rows.first().click();await main.locator('.cg-toolbar').getByRole('button',{name:'Delete',exact:true}).click();let deletion=await pageFor('tool=delete');await deletion.waitForSelector('[role=dialog]');assert.equal(await deletion.getByLabel('Also delete the file from disk').isChecked(),false);await bothThemes(deletion,'delete-dialog',settings);await deletion.getByRole('dialog').getByRole('button',{name:'Yes',exact:true}).click();await until(async()=>(await ipc({query:'list'})).downloads.length===1,'List entry was not removed');await access(destination);passed('Delete confirmation removes the entry and keeps the downloaded file by default');
 await main.locator('.cg-row').first().click();await main.locator('.cg-toolbar').getByRole('button',{name:'Delete',exact:true}).click();deletion=await pageFor('tool=delete');await deletion.getByLabel('Also delete the file from disk').check();await deletion.getByRole('dialog').getByRole('button',{name:'Yes',exact:true}).click();await until(async()=>(await ipc({query:'list'})).downloads.length===0,'Disk-delete entry was not removed');await until(async()=>{try{await access(path.join(folder,'downloads','fixture-thirty-two.zip'));return false}catch{return true}},'Downloaded file was not removed');passed('Optional disk deletion removes the actual test file');
 await bothThemes(settings,'settings',settings);
 await settings.getByRole('button',{name:'Glass & scaling',exact:true}).click();await settings.getByLabel(/Interface size/).focus();await settings.getByLabel(/Interface size/).press('End');
 await settings.getByRole('button',{name:'Typography',exact:true}).click();await settings.getByLabel(/Text size/).focus();await settings.getByLabel(/Text size/).press('End');
 await assertFits(settings,'Largest typography and scaling in Settings');await assertFits(main,'Largest typography and scaling in main');await screenshot(settings,'settings-large-typography');await screenshot(main,'main-large-typography');
 await settings.getByRole('button',{name:'Restore default Glass appearance',exact:true}).click();
 passed('Large typography and interface scaling adapt across native windows');
 passed('Dark/light appearance propagates across native windows; screenshots captured');
 results.push({name:'Explorer/application native drag and physical DPI/transparency review',status:'manual Windows review still required'});
 await writeFile(path.join(output,'results.json'),JSON.stringify({platform:process.platform,arch:process.arch,source_run:process.env.GLASS_E2E_SOURCE_RUN??process.env.GITHUB_RUN_ID,results},null,2));
 console.log('Windows native acceptance passed. Screenshots and result evidence are in the proof artifact.');
}catch(error){
 await writeFile(path.join(output,'shell-startup.txt'),JSON.stringify({exit:shellExit,output:shellError},null,2));
 const diagnostic=spawnSync('powershell.exe',['-NoProfile','-Command',"Get-CimInstance Win32_Process | Where-Object {$_.Name -match 'mister|msedge|webview'} | Select-Object Name,ProcessId,CommandLine | Format-List"],{encoding:'utf8'});
 await writeFile(path.join(output,'processes.txt'),diagnostic.stdout||diagnostic.stderr||'No process diagnostics');
 const desktop=spawnSync('powershell.exe',['-NoProfile','-Command',"Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $bounds=[System.Windows.Forms.SystemInformation]::VirtualScreen; $bitmap=New-Object System.Drawing.Bitmap $bounds.Width,$bounds.Height; $graphics=[System.Drawing.Graphics]::FromImage($bitmap); $graphics.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$bitmap.Size); $bitmap.Save('"+path.join(output,'windows-desktop.png').replaceAll("'","''")+"'); $graphics.Dispose(); $bitmap.Dispose()"],{encoding:'utf8'});
 if(desktop.status!==0)await writeFile(path.join(output,'desktop-capture.txt'),desktop.stderr||desktop.stdout||'No interactive desktop');

 console.error(error.stack||error.message);results.push({name:error.message,status:'failed'});
 if(browser)for(const [i,page] of browser.contexts().flatMap(c=>c.pages()).entries())if(!page.isClosed())await screenshot(page,'failure-'+i).catch(()=>{});
 await writeFile(path.join(output,'results.json'),JSON.stringify({platform:process.platform,arch:process.arch,source_run:process.env.GLASS_E2E_SOURCE_RUN??process.env.GITHUB_RUN_ID,results},null,2));process.exitCode=1;
}finally{
 if(browser){for(const page of browser.contexts().flatMap(c=>c.pages())){if(!page.isClosed()){await invoke(page,'quit_glass').catch(()=>{});break}}await browser.close().catch(()=>{});}
 if(shell&&!shell.killed)spawnSync('taskkill',['/PID',String(shell.pid),'/T','/F'],{stdio:'ignore'});
 server.closeAllConnections();await new Promise(r=>server.close(r));
}
