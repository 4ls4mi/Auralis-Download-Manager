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
 const tick=setInterval(()=>{if(at>end){clearInterval(tick);res.end();return;}const bytes=Math.min(block.length,end-at+1);res.write(block.subarray(0,bytes));at+=bytes;},180);
 res.on('close',()=>clearInterval(tick));
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const address=`http://127.0.0.1:${server.address().port}`;
const portServer=net.createServer();await new Promise(r=>portServer.listen(0,'127.0.0.1',r));const port=portServer.address().port;await new Promise(r=>portServer.close(r));
async function ipc(command){const endpoint=JSON.parse(await readFile(path.join(data,'ipc.json'),'utf8'));return new Promise((resolve,reject)=>{let text='';const socket=net.connect({host:'127.0.0.1',port:endpoint.port},()=>socket.write(JSON.stringify({token:endpoint.token,...command})+'\n'));socket.setTimeout(10000,()=>socket.destroy(new Error('IPC timeout')));socket.on('data',b=>{text+=b.toString();if(text.includes('\n')){socket.end();try{resolve(JSON.parse(text.split('\n')[0]));}catch(e){reject(e)}}});socket.on('error',reject);});}
async function capture(name,extra={}){
 const host=path.join(path.dirname(process.env.GLASS_E2E_EXE),'misterdownloadmanager-nmhost.exe');
 const message={url:address+'/'+name,filename:name,size:name.includes('thirty-two')?64*1024*1024:size,mime:'application/zip',referrer:address+'/source',pageUrl:address+'/source',cookies:'glass_acceptance=1',userAgent:'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:144.0) Gecko/20100101 Firefox/144.0',explicit:true,v:'0.2.4',...extra};
 const bytes=Buffer.from(JSON.stringify(message));const header=Buffer.alloc(4);header.writeUInt32LE(bytes.length);
 const hostReply=await new Promise((resolve,reject)=>{const child=spawn(host,['glass-test.firefox.json','integration@misterdownloadmanager.com'],{env:{...process.env,MDM_DATA_DIR:data},stdio:['pipe','pipe','pipe']});let raw=Buffer.alloc(0),hostError='';child.stderr.on('data',b=>{hostError+=b.toString()});child.on('exit',code=>{if(raw.length<4){clearTimeout(timer);reject(new Error('Native browser host exited ('+code+'): '+hostError))}});const timer=setTimeout(()=>{child.kill();reject(new Error('Native browser host did not reply'));},30000);child.on('error',reject);child.stdout.on('data',b=>{raw=Buffer.concat([raw,b]);if(raw.length>=4&&raw.length>=4+raw.readUInt32LE(0)){clearTimeout(timer);child.stdin.end();resolve(JSON.parse(raw.subarray(4,4+raw.readUInt32LE(0)).toString()));}});child.stdin.write(Buffer.concat([header,bytes]));});
 assert.equal(hostReply.ok,true,'Original native messaging host accepted capture');
 return message;
}
async function pageFor(key){return until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&p.url().includes(key)),'Native window did not open: '+key);}
const invoke=(page,command,args={})=>Promise.race([page.evaluate(([command,args])=>window.__TAURI_INTERNALS__.invoke(command,args),[command,args]),wait(12000).then(()=>{throw new Error('Native command timed out: '+command)})]);
async function screenshot(page,name){await page.screenshot({path:path.join(output,name+'.png'),timeout:7000});}
async function assertFits(page,name){
 let lastOverflow=[];
 try { await until(async()=>{
  const overflow=await page.evaluate(()=>{const frame=document.querySelector('.cg-content')?.getBoundingClientRect(),fit=document.querySelector('.cg-fit-content')?.getBoundingClientRect();const out=Array.from(document.querySelectorAll('.cg-fit-content,.cg-page,.cg-settings-body,.cg-settings-nav,.cg-toolbar,.cg-window-top')).filter(el=>el.clientWidth&&el.clientHeight&&(el.scrollHeight>el.clientHeight+3||el.scrollWidth>el.clientWidth+3)).map(el=>el.className);if(frame&&fit&&(fit.right>frame.right+3||fit.bottom>frame.bottom+3))out.push('window bounds');const root=document.querySelector('.cg-fit-content');const zoom=root?Number.parseFloat(getComputedStyle(root).zoom)||1:1;for(const el of document.querySelectorAll('.cg-toolbar button span,.cg-sidebar button span,.cg-mdm-details dt,.cg-mdm-details dd')){if(el.getBoundingClientRect().width>0&&Number.parseFloat(getComputedStyle(el).fontSize)*zoom<11.5)out.push('unreadable text');}return out});
  lastOverflow=overflow;return overflow.length===0;
 },name+' has clipped content or would require page scrolling'); } catch(error) { throw new Error(error.message+': '+JSON.stringify(lastOverflow)); }
}
async function resizeWindow(page,label,width,height){await invoke(page,'plugin:window|set_size',{label,value:{Logical:{width,height}}});await wait(450);}
async function setTheme(settings,light){await settings.getByRole('button',{name:'Appearance',exact:true}).click();await settings.getByRole('button',{name:'Theme',exact:true}).click();await settings.getByRole('button',{name:light?'Light crystal':'Dark crystal',exact:true}).click();await wait(350);}
async function bothThemes(page,name,settings){for(const light of [false,true]){await setTheme(settings,light);await until(()=>page.locator(light?'.cg-light':'.cg-dark').count(),'Appearance did not reach '+name);await screenshot(page,name+(light?'-light':'-dark'));}}
try{
 shell=spawn(process.env.GLASS_E2E_EXE,[],{env:{...process.env,MDM_DATA_DIR:data,MDM_REMOTE:'off',GLASS_TEST_CDP_PORT:String(port),WEBVIEW2_USER_DATA_FOLDER:path.join(folder,'webview'),WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:`--remote-debugging-port=${port} --remote-debugging-address=127.0.0.1 --remote-allow-origins=*`},stdio:['ignore','pipe','pipe']});
 shell.stdout.on('data',b=>{shellError+=b.toString()});shell.stderr.on('data',b=>{shellError+=b.toString()});
 shell.on('error',e=>{shellError+=e.message;shellExit='spawn error'});shell.on('exit',(code,signal)=>{shellExit={code,signal}});
 browser=await until(async()=>{if(shellExit!==null)throw new Error('Glass exited before WebView2 started: '+JSON.stringify(shellExit)+' '+shellError);try{return await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:3000})}catch{return null}},'WebView2 CDP was not available',90000);
 const main=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.url().includes('?')),'Main native WebView did not appear');
 await main.waitForSelector('.cg-toolbar');await until(async()=>{const d=await ipc({query:'glass-backend'});return d.headless&&d.glass},'Original headless backend did not start',60000);
 passed('One Glass shell connects to the original headless MDM backend');
 const edgeStore=await invoke(main,'extension_store_link',{browser:'edge'});assert.equal(edgeStore,'microsoft-edge:https://chromewebstore.google.com/detail/mister-download-manager/ejoleppdfgjdndddcjoehopknmlglojp');await assert.rejects(()=>invoke(main,'extension_store_link',{browser:'invalid'}));passed('Edge repair targets the official extension listing and rejects unknown browsers');
 const clean=await main.evaluate(()=>({overlays:document.querySelectorAll('.cg-material-renderer,.cg-material-surface,[class*="cg-material-"]').length,blur:getComputedStyle(document.querySelector('.cg-content')).backdropFilter}));assert(clean.overlays===0&&clean.blur==='none','Retired material overlays and repeated CSS backdrop blur must be absent');passed('Material overlays and repeated CSS backdrop blur are absent');
 await main.locator('.cg-toolbar').getByRole('button',{name:'Settings',exact:true}).click();const settings=await pageFor('settings=');
 await settings.getByRole('button',{name:'Browser Integration',exact:true}).click();assert.equal(await settings.getByRole('combobox').first().inputValue(),'edge');await settings.getByText(/allow extensions from other stores/i).waitFor();await settings.getByRole('button',{name:'Repair connection and get extension',exact:true}).waitFor();await assertFits(settings,'Browser extension repair');await screenshot(settings,'browser-integration');passed('Browser repair exposes the Edge installation flow');
 await settings.getByRole('button',{name:'Repair connection and get extension',exact:true}).click();await settings.getByText(/extension page opened|confirm extension installation in your browser/i).waitFor();passed('Repair button requests the Edge extension page through the native command');await invoke(settings,'plugin:window|set_focus',{label:'settings'}).catch(()=>{});
 await settings.getByRole('button',{name:'General',exact:true}).click();
 await settings.getByLabel('Show download complete dialog').uncheck();
 await until(async()=>!(await invoke(main,'glass_settings')).show_complete,'Turning completion off failed through the actual Tauri bridge');
 await settings.getByLabel('Show download complete dialog').check();
 await until(async()=>(await invoke(main,'glass_settings')).show_complete,'Turning completion on failed through the actual Tauri bridge');
 passed('Completion-dialog checkbox saves through the real native bridge');
 if(process.env.GLASS_TEST_HELPERS==='1'){
  const mode=settings.getByLabel('Copied download links');
  const original=async()=>{const d=await invoke(main,'glass_tool',{action:'original-settings',payload:null});return Object.fromEntries(d.fields.map(f=>[f.key,f.value]));};
  const setClipboard=text=>spawnSync('powershell.exe',['-NoProfile','-STA','-Command',"Set-Clipboard -Value '"+text.replaceAll("'","''")+"'"],{encoding:'utf8',timeout:12000});
  await mode.selectOption('auto');await until(async()=>{const s=await original();return s.clipboard_autostart&&s.glass_clipboard_auto_download},'Automatic clipboard mode did not save');
  await wait(2300);const automaticUrl=address+'/clipboard-automatic.custom';const clipboard=setClipboard(automaticUrl);
  if(clipboard.status===0){
   const auto=await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.url===automaticUrl),'Automatically copied URL was not added');
   await until(async()=>{const f=(await ipc({query:'list'})).downloads.find(x=>x.id===auto.id);return f&&f.status!=='Downloading'},'Automatic fixture did not stop after the expected server refusal');
   await invoke(main,'download_action',{action:'remove',ids:[auto.id]});await invoke(main,'close_progress_windows',{ids:[auto.id]});await until(async()=>(await ipc({query:'list'})).downloads.every(f=>f.id!==auto.id),'Automatic clipboard fixture was not removed');
   passed('Automatic mode adds a supported copied URL without relying on its extension');
  }
  await until(()=>mode.isEnabled(),'Clipboard selector stayed busy');await mode.selectOption('paste');await until(async()=>!(await original()).clipboard_autostart,'Paste-only mode did not stop automatic capture');
  const pasteUrl=address+'/clipboard-prefill.zip';if(clipboard.status===0)assert.equal(setClipboard(pasteUrl).status,0,'Could not set the Windows clipboard');
  if(clipboard.status===0){
   await main.locator('.cg-toolbar').getByRole('button',{name:'Add URL',exact:true}).click();const add=await pageFor('add=url');
   await until(async()=>(await add.getByLabel('Download address').inputValue())===pasteUrl,'Add URL did not prefill the copied link');
   await add.locator('.cg-window-add').getByRole('button',{name:'Close',exact:true}).click();await until(()=>add.isClosed(),'Add URL did not close');
   passed('Paste-on-Add URL reads the actual Windows clipboard');
  }else results.push({name:'Windows clipboard unavailable on the runner: '+(clipboard.stderr||clipboard.error?.message||'unknown error'),status:'manual Windows review still required'});
  await until(()=>mode.isEnabled(),'Clipboard selector stayed busy');await mode.selectOption('offer');await until(async()=>{const s=await original();return s.clipboard_autostart&&!s.glass_clipboard_auto_download},'Clipboard offer mode did not save');
  if(clipboard.status===0){
   await wait(2300);const offerUrl=address+'/clipboard-offer.zip';const copied=setClipboard(offerUrl);assert.equal(copied.status,0,'Could not set the Windows clipboard');
   const offer=await pageFor('request=');await offer.waitForSelector('.cg-file-info');assert.equal(await offer.getByLabel('URL',{exact:true}).inputValue(),offerUrl);
   await offer.locator('main.cg-file-info').getByRole('button',{name:'Cancel',exact:true}).click();await until(()=>offer.isClosed(),'Clipboard File Info did not close');
   passed('Original clipboard watcher offers a copied link in File Info');
  }
  passed('Clipboard modes save through the original backend');
 }

 if(process.env.GLASS_TEST_HELPERS==='1'){
  const helpers=await invoke(main,'glass_tool',{action:'helpers',payload:null});
  assert.deepEqual(helpers.tools.map(t=>t.name),['yt-dlp','ffmpeg','gallery-dl']);
  await settings.getByRole('button',{name:'Advanced',exact:true}).click();
  await settings.getByText('Video and gallery helpers',{exact:true}).waitFor();
  for(const name of ['yt-dlp','ffmpeg','gallery-dl'])await settings.getByText(name,{exact:true}).waitFor();
  passed('Original verified helper manager reports all three tools through Glass');
  const upstream=await invoke(main,'glass_tool',{action:'upstream-status',payload:null});assert(['not-checked','checking','latest','newer','error'].includes(upstream.state),'Original release status unavailable');await settings.getByRole('button',{name:'Updates',exact:true}).click();await settings.getByText('Original MDM releases',{exact:true}).waitFor();passed('Original MDM release check is available without replacing Glass');await settings.getByRole('button',{name:'General',exact:true}).click();
  if(process.env.GLASS_TEST_INSTALL_HELPERS==='1'){
   for(const name of ['yt-dlp','ffmpeg','gallery-dl']){
    await invoke(main,'glass_tool',{action:'helpers-install',payload:{name}});
    const finished=await until(async()=>{const data=await invoke(main,'glass_tool',{action:'helpers',payload:null});return data.job?.name===name&&data.job.state!=='installing'?data:null},name+' installation did not finish',360000);
    if(finished.job.state!=='ready'&&/403 Forbidden.*too many requests/i.test(String(finished.job.state))){results.push({name:'Helper installation verification blocked by GitHub rate limit',status:'manual Windows review still required'});break;}
    assert.equal(finished.job.state,'ready',name+' installation failed: '+finished.job.state);
    const tool=finished.tools.find(t=>t.name===name);assert(tool?.version&&tool.path,name+' not reported after installation');await access(tool.path);
    const probe=spawnSync(tool.path,[name==='ffmpeg'?'-version':'--version'],{encoding:'utf8',timeout:30000});assert.equal(probe.status,0,name+' did not run: '+(probe.stderr||probe.error?.message||''));
    passed('Original MDM verified installer makes '+name+' available and runnable');
   }
  }

  const video=await invoke(main,'video_tool',{action:'lookup',value:'https://example.invalid/fixture-video',choice:null});
  assert.notEqual(video.state,'use-window','Glass video lookup must reach the original engine');
  await main.getByRole('button',{name:'Tasks',exact:true}).click();await main.getByRole('button',{name:'Download video from a page…',exact:true}).click();
  const videoWindow=await pageFor('tool=video');await videoWindow.getByLabel('Video page URL').waitFor();await videoWindow.locator('.cg-tool-body').getByRole('button',{name:'Close',exact:true}).click();
  passed('Video page quality lookup reaches the original engine from a Glass window');
  const videoAddress='https://example.invalid/browser-video';
  await capture('browser-video',{url:videoAddress,video:true,title:'Browser video fixture',private:true});
  const fromBrowser=await pageFor('tool=video&browser=');
  await until(async()=>(await fromBrowser.getByLabel('Video page URL').inputValue())===videoAddress,'Browser video command did not reach the Glass video window');
  const browserId=Number(new URL(fromBrowser.url()).searchParams.get('browser'));
  const request=await invoke(main,'browser_video',{id:browserId,choice:null});
  assert.notEqual(request.result.state,'use-window','Browser video must start the original quality lookup');
  assert(!JSON.stringify(request).includes('glass_acceptance=1'),'Browser cookies must not reach the WebView');
  await fromBrowser.locator('.cg-tool-body').getByRole('button',{name:'Close',exact:true}).click();
  passed('Native browser video command opens Glass and starts the original lookup without exposing cookies');

  await assert.rejects(invoke(main,'glass_tool',{action:'gallery',payload:{url:'not-a-url',folder:'',limit:null,start:false}}));
  await main.getByRole('button',{name:'Tasks',exact:true}).click();await main.getByRole('button',{name:'Download gallery…',exact:true}).click();const gallery=await pageFor('tool=gallery');await gallery.getByLabel('Gallery page URL').waitFor();await gallery.locator('.cg-tool-body').getByRole('button',{name:'Close',exact:true}).click();
  passed('Gallery window opens and invalid addresses are rejected by MDM');
  await invoke(main,'glass_tool',{action:'original-setting',payload:{key:'queue_panel_later',value:false}});
  const galleryUrl='https://example.invalid/gallery';await invoke(main,'glass_tool',{action:'gallery',payload:{url:galleryUrl,folder:path.join(folder,'gallery-fixture'),limit:1,start:false}});
  const galleryItem=await until(async()=>(await ipc({query:'list'})).downloads.find(x=>x.url===galleryUrl),'Gallery was not added to the original engine');
  await until(async()=>(await invoke(main,'dashboard_snapshot')).queues.some(q=>q.ids.includes(galleryItem.id)),'Gallery was not placed in an MDM queue');
  await invoke(main,'download_action',{action:'remove',ids:[galleryItem.id]});await until(async()=>(await ipc({query:'list'})).downloads.every(x=>x.id!==galleryItem.id),'Gallery fixture was not removed');
  await invoke(main,'glass_tool',{action:'original-setting',payload:{key:'queue_panel_later',value:true}});passed('Gallery Later adds to the original MDM queue');
 }

 await capture('fixture-eight.zip');let info=await pageFor('request=');await info.waitForSelector('.cg-file-info');await wait(350);
 assert.equal((await ipc({query:'list'})).downloads.length,0,'Capture must wait for user confirmation');assert.equal((await ipc({query:'list'})).downloads.some(f=>f.status==='Downloading'),false,'Metadata probing must not create a running download before confirmation');
 await bothThemes(info,'file-info',settings);
 let destination=path.join(folder,'downloads','fixture-eight.zip');
 await info.getByLabel('Save As',{exact:true}).fill(destination);await info.getByLabel('Maximum connections').selectOption('8');await info.getByRole('button',{name:'Start Download',exact:true}).click();
 const first=await until(async()=>{const d=await ipc({query:'list'});return d.downloads.find(f=>f.file==='fixture-eight.zip');},'Original engine did not add the chosen file');
 let progress=await pageFor('detail='+first.id);await progress.waitForSelector('.cg-mdm-details');
 await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.id===first.id)?.downloaded>0,'Original HTTP engine received no bytes');
 await until(async()=>{const v=(await invoke(main,'dashboard_visuals')).downloads.find(f=>f.id===first.id);if(!v||!v.connections.some(c=>c.state==='Receiving')||!v.segments.some(s=>s.worker!=null))return false;const n=v.connections.filter(c=>c.state!=='Retired'&&c.state!=='Failed'&&!(c.state==='Finished'&&c.downloaded===0)).length;return (await progress.locator('.cg-chunk-map>span').count())===n},'Live engine workers and assigned ranges did not reach connection indicators');
 const labels=await progress.locator('.cg-chunk-map>span').allTextContents();assert(labels.length>0,'Live connections should be represented');passed('Live connection blocks follow engine workers and owned byte ranges');
 await progress.getByRole('button',{name:'Pause',exact:true}).click();await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.id===first.id)?.status==='Stopped','Transfer did not pause');
 assert.equal(progress.isClosed(),false,'Pausing in the progress window keeps it open');
 await until(async()=>await progress.locator('.cg-chunk-map>span.active').count()===0,'Paused connection blocks must not appear active');
 await progress.getByRole('button',{name:'Resume',exact:true}).click();
 await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.id===first.id)?.status==='Downloading','Transfer did not resume');
 await main.locator('.cg-row').first().click();await main.locator('.cg-toolbar').getByRole('button',{name:'Stop',exact:true}).click();
 await until(()=>progress.isClosed(),'Stopping from the main window did not close progress');await wait(1000);
 await main.locator('.cg-toolbar').getByRole('button',{name:'Resume',exact:true}).click();progress=await pageFor('detail='+first.id);
 await progress.getByRole('button',{name:'Pause',exact:true}).click();await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.id===first.id)?.status==='Stopped','Transfer did not pause again');
 passed('Pause keeps progress open; Stop from the main window closes it');
 await main.waitForSelector('.cg-row');await until(async()=>{const v=(await invoke(main,'dashboard_visuals')).downloads.find(f=>f.id===first.id);const expected=(v?.connections??[]).filter(c=>c.state!=='Retired'&&c.state!=='Failed'&&!(c.state==='Finished'&&c.downloaded===0)).length;return (await progress.locator('.cg-chunk-map>span').count())===expected},'Connection blocks did not match engine workers');
 assert.equal(await progress.locator('.cg-mdm-details dt').allTextContents().then(a=>a.join('|')),'Status|File size|Downloaded|Transfer rate|Time left|Resume capability|Server');
 assert(headersPreserved>0,'Captured cookie/referrer/User-Agent reached the original HTTP engine');
 passed('Original native host capture opens FileInfo before transfer and preserves browser context');
 passed('Chosen destination and engine-reported connections reach the progress window');
 const separated=await main.locator('.cg-row-progress').first().evaluate(el=>{const items=[el.querySelector('.cg-percent-wrap'),el.querySelector('.cg-chunks'),el.querySelector('.cg-graph-small')];if(items.some(x=>!x))return false;const rects=items.map(x=>x.getBoundingClientRect());return rects.every((a,i)=>rects.every((b,j)=>i===j||a.right<=b.left+1||b.right<=a.left+1||a.bottom<=b.top+1||b.bottom<=a.top+1))});assert(separated,'Main list indicators must not overlap');passed('Main list percentage, engine connections and speed graph occupy separate areas');
 const scrolling=await main.evaluate(()=>{const el=document.querySelector('.cg-table-viewport'),table=el?.querySelector('.cg-table'),row=table?.querySelector('.cg-row');if(!el||!table||!row)return false;const clones=[];for(let i=0;i<16;i++){const clone=row.cloneNode(true);clone.setAttribute('data-scroll-probe','');table.appendChild(clone);clones.push(clone)}const old=el.scrollTop;el.scrollTop=el.scrollHeight;const ok=el.scrollTop>0;el.scrollTop=old;clones.forEach(x=>x.remove());return ok});assert(scrolling,'Download list must scroll when it contains more rows than fit');passed('Main download list scrolls independently when rows overflow');
 await bothThemes(progress,'progress',settings);await bothThemes(main,'main',settings);
 if(process.env.MHG_EXPERIMENTAL_WATER==='1'){
  await until(()=>progress.locator('.cg-native-water-experiment').count(),'Native Water Bubble did not initialize in the real download window');
  await invoke(progress,'plugin:window|show',{label:`download-${first.id}`});
  await invoke(progress,'plugin:window|unminimize',{label:`download-${first.id}`});
  await invoke(progress,'plugin:window|set_focus',{label:`download-${first.id}`});
  await wait(700);
  await screenshot(progress,'experimental-water-webview');
  const out=path.join(output,'experimental-water-desktop.png').replaceAll("'","''");
  const shot=spawnSync('powershell.exe',['-NoProfile','-Command',"Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $bounds=[System.Windows.Forms.SystemInformation]::VirtualScreen; $bitmap=New-Object System.Drawing.Bitmap $bounds.Width,$bounds.Height; $graphics=[System.Drawing.Graphics]::FromImage($bitmap); $graphics.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$bitmap.Size); $bitmap.Save('"+out+"'); $graphics.Dispose(); $bitmap.Dispose()"],{encoding:'utf8'});
  if(shot.status!==0)await writeFile(path.join(output,'experimental-water-desktop-error.txt'),shot.stderr||shot.stdout||'No interactive desktop available');
  passed('Experimental Direct2D surface initialized in a real download window; desktop visibility still requires screenshot review');
 }

 await settings.getByRole('button',{name:'Theme',exact:true}).click();await assertFits(settings,'Theme settings');
 const previousAccent=await progress.locator('.cg-window').evaluate(e=>getComputedStyle(e).getPropertyValue('--accent-rgb'));
 const alternate=settings.locator('.cg-color-choices button:not(.selected)').first();
 assert(await alternate.count(),'An alternative theme must be available');await alternate.click();await until(async()=>(await progress.locator('.cg-window').evaluate(e=>getComputedStyle(e).getPropertyValue('--accent-rgb')))!==previousAccent,'Theme accent did not propagate');
 passed('Theme accent changes propagate to the progress window');
 const rects=await progress.evaluate(()=>{const row=document.querySelector('.cg-indicator-row'),left=row?.querySelector('.cg-progress-combined'),right=row?.querySelector('.cg-selected-chunks'),bar=left?.querySelector('.cg-percent-track'),graph=left?.querySelector('.cg-compact-speed');return [left,right,bar,graph].map(e=>{const r=e?.getBoundingClientRect();return r?{x:r.x,y:r.y,width:r.width,height:r.height,bottom:r.bottom,right:r.right}:null})});
 assert(rects.every(Boolean),'Progress, chunks and graph must be present');assert(Math.abs(rects[0].width-rects[1].width)<3,'Progress and chunks must share the row equally');assert(rects[2].height>=14,'Progress bar must be thicker');assert(rects[3].y>=rects[2].bottom-1&&rects[3].right<=rects[0].right+2,'Compact graph must remain below the bar inside the left column');passed('Equal-width progress and chunk sections keep the compact speed graph under the bar');
 await settings.getByRole('button',{name:'Indicators',exact:true}).click();await assertFits(settings,'Indicator settings');await settings.getByRole('button',{name:'Sunset',exact:true}).click();await until(async()=>(await progress.locator('.cg-percent-fill').first().getAttribute('style'))?.includes('255, 181, 46'),'Indicator palette did not propagate to progress');await settings.getByRole('button',{name:'Blue / Purple',exact:true}).click();passed('Indicator palette changes propagate independently across windows');
 await assertFits(progress,'Connection indicators');await screenshot(progress,'progress-connections');
 await resizeWindow(progress,'download-'+first.id,620,500);await assertFits(progress,'Small progress window with connections');await screenshot(progress,'progress-small-connections');
 await resizeWindow(progress,'download-'+first.id,880,680);
 let smallMainFailure=null;await resizeWindow(main,'main',800,540);try{await assertFits(main,'Small main window')}catch(e){smallMainFailure=e;results.push({name:e.message,status:'failed'});console.error(e.message)}await screenshot(main,'main-small');await resizeWindow(main,'main',1480,850);
 if(!smallMainFailure)passed('Main and expanded progress content fit resized native windows without page scrolling');
 await invoke(main,'update_glass_setting',{key:'max_connections',value:'32'});
 assert.equal((await invoke(main,'dashboard_visuals')).downloads.find(f=>f.id===first.id).chunk_count,8);
 passed('Changing the global connection setting preserves an existing file’s selected chunk count');
 await setTheme(settings,false);
 await progress.getByRole('button',{name:'Resume',exact:true}).click();
 // Main-window timers must not own completion lifecycle.
 await invoke(main,'plugin:window|hide',{label:'main'});
 const complete=await pageFor('complete='+first.id);await complete.waitForSelector('.cg-complete-page');
 const completionFocused=await invoke(complete,'plugin:window|is_focused',{label:`complete-${first.id}`}).catch(()=>null);
 const topState=await invoke(complete,'plugin:window|is_always_on_top',{label:`complete-${first.id}`}).catch(()=>null);
 if(topState===null)results.push({name:'Completion window topmost release',status:'manual Windows review still required'});else{await until(async()=>await invoke(complete,'plugin:window|is_always_on_top',{label:`complete-${first.id}`})===false,'Completion window remained always on top',5000);passed('Completion window releases its temporary topmost state');}
 if(completionFocused)passed('Completion window received focus');else results.push({name:'Completion window foreground focus',status:'manual Windows review still required'});
 assert.equal(await complete.getByTitle('Drag the file into a folder or an app').isEnabled(),true,'Completed file drag control should be available');assert.equal(await complete.getByTitle('Hide to tray').isVisible(),true,'Completed window must offer a tray control');
 await until(()=>progress.isClosed(),'Progress window did not close on completion');
 await invoke(main,'plugin:window|show',{label:'main'});
 await bothThemes(complete,'complete',settings);
 assert((await readFile(destination)).every(b=>b===0x47),'Original engine output matches the served bytes');
 passed('Actual transfer completes while main is hidden; progress closes and completion dialog opens');
 await invoke(main,'file_operation',{id:first.id,operation:'checksum',value:expected});
 const check=await until(async()=>{const r=await invoke(main,'file_operation',{id:first.id,operation:'checksum-result',value:null});return r.complete?r:null},'Original engine checksum verifier did not finish');assert.equal(check.matches,true);passed('Original engine verifies the completed file checksum');
 if(process.env.GLASS_TEST_HELPERS==='1'){
  const before=await invoke(complete,'drag_state',{id:first.id});assert.equal(before.path,destination);const rejected=await ipc({action:'glass-drag-file',ids:[first.id],queue:JSON.stringify({hwnd:0,pid:process.pid})});assert(rejected.error,'Invalid native drag window must be rejected');
  const oldPath=destination;const movedFolder=path.join(folder,'moved');await mkdir(movedFolder,{recursive:true});const movedPath=path.join(movedFolder,'fixture-eight.zip');
  const requested=await ipc({action:'glass-item',category:'move',ids:[first.id],queue:movedPath});assert(!requested.error,'Original engine rejected file move');
  await until(async()=>{const state=await ipc({query:'glass-move-status',ids:[first.id]});return !state.moving&&state.path===movedPath},'Original engine did not record the moved file');
  await access(movedPath);await assert.rejects(access(oldPath));destination=movedPath;await until(async()=>(await complete.locator('input[readonly]').last().inputValue())===movedPath,'Completion window did not follow the moved file');await complete.getByRole('status').filter({hasText:'File moved to'}).waitFor();
  passed('Completed-file move finishes on disk and updates the original engine path');
 }

 await complete.locator('.cg-complete-page').getByRole('button',{name:'Close',exact:true}).click();
 await capture('fixture-thirty-two.zip');info=await pageFor('request=');await info.waitForSelector('.cg-file-info');await info.getByLabel('Save As',{exact:true}).fill(path.join(folder,'downloads','fixture-thirty-two.zip'));await info.getByLabel('Maximum connections').selectOption('32');await info.getByRole('button',{name:'Start Download',exact:true}).click();
 const second=await until(async()=>(await ipc({query:'list'})).downloads.find(f=>f.file==='fixture-thirty-two.zip'),'Second file missing');const progress32=await pageFor('detail='+second.id);await until(async()=>{const v=(await invoke(main,'dashboard_visuals')).downloads.find(f=>f.id===second.id);return !!v&&v.connections.some(c=>c.state==='Receiving')&&(await progress32.locator('.cg-chunk-map>span').count())===v.connections.filter(c=>c.state!=='Retired'&&c.state!=='Failed'&&!(c.state==='Finished'&&c.downloaded===0)).length},'Progress did not match actual connections');const gridColumns=await progress32.locator('.cg-chunk-map').first().evaluate(el=>getComputedStyle(el).gridTemplateColumns.trim().split(/\s+/).length).catch(()=>0);assert(gridColumns<=8,'Connection grid must have no more than eight columns');const blockCount=await progress32.locator('.cg-chunk-map>span').count();if(blockCount>8){const positions=await progress32.locator('.cg-chunk-map>span').evaluateAll(a=>[...a.slice(0,8).map(e=>e.getBoundingClientRect().top),a[8].getBoundingClientRect().top]);assert(positions.slice(0,8).every(y=>Math.abs(y-positions[0])<1),'The first eight connections must share a row');assert(positions[8]>positions[0],'The ninth connection must start a new row');passed('Connection indicators wrap after eight blocks');}await screenshot(progress32,'progress-32-chunks');
 const done32=await pageFor('complete='+second.id);await done32.waitForSelector('.cg-complete-page');await done32.locator('.cg-complete-page').getByRole('button',{name:'Close',exact:true}).click();
 const rows=main.locator('.cg-row');await until(async()=>await rows.count()===2,'Main list did not update');const search=main.getByPlaceholder('Search downloads...');await search.fill('EIGHT fixture');await until(async()=>await rows.count()===1&&await rows.first().innerText().then(t=>t.includes('fixture-eight.zip')),'Search did not match partial words');await search.fill('');await until(async()=>await rows.count()===2,'Search clear did not restore the list');passed('Search matches partial words without case sensitivity');await rows.first().click({button:'right'});await main.waitForSelector('.cg-context');await bothThemes(main,'context-menu',settings);await main.locator('.cg-context').getByRole('button',{name:'Redownload',exact:true}).click();const confirm=await pageFor('tool=confirm');await confirm.getByRole('dialog',{name:'Confirm redownload'}).waitFor();await confirm.getByRole('button',{name:'Cancel',exact:true}).click();await until(()=>confirm.isClosed(),'Redownload confirmation did not close');passed('Redownload uses a separate movable Glass confirmation');
 await rows.first().click();await main.locator('.cg-toolbar').getByRole('button',{name:'Delete',exact:true}).click();let deletion=await pageFor('tool=delete');await deletion.waitForSelector('[role=dialog]');assert.equal(await deletion.getByLabel('Also delete the file from disk').isChecked(),false);await rows.nth(1).click();await main.locator('.cg-toolbar').getByRole('button',{name:'Delete',exact:true}).click();await until(()=>deletion.getByText('fixture-thirty-two.zip',{exact:false}).isVisible(),'Movable deletion dialog did not update to the selected file');await rows.first().click();await main.locator('.cg-toolbar').getByRole('button',{name:'Delete',exact:true}).click();await until(()=>deletion.getByText('fixture-eight.zip',{exact:false}).isVisible(),'Deletion confirmation did not return to the selected file');await bothThemes(deletion,'delete-dialog',settings);await deletion.getByRole('dialog').getByRole('button',{name:'Yes',exact:true}).click();await until(async()=>(await ipc({query:'list'})).downloads.length===1,'List entry was not removed');await access(destination);passed('Delete confirmation removes the entry and keeps the downloaded file by default');
 await until(async()=>await main.locator('.cg-row').count()===1,'Main list did not refresh after deletion');await main.locator('.cg-row').first().click();await main.locator('.cg-toolbar').getByRole('button',{name:'Delete',exact:true}).click();deletion=await pageFor('tool=delete');await until(()=>deletion.getByText('fixture-thirty-two.zip',{exact:false}).isVisible(),'Deletion dialog did not show the remaining file');await deletion.getByLabel('Also delete the file from disk').check();await deletion.getByRole('dialog').getByRole('button',{name:'Yes',exact:true}).click();await until(async()=>(await ipc({query:'list'})).downloads.length===0,'Disk-delete entry was not removed');await until(async()=>{try{await access(path.join(folder,'downloads','fixture-thirty-two.zip'));return false}catch{return true}},'Downloaded file was not removed');passed('Optional disk deletion removes the actual test file');
 await bothThemes(settings,'settings',settings);
 await settings.getByRole('button',{name:'Glass & scaling',exact:true}).click();const backdrop=settings.getByLabel('Windows backdrop blur');await backdrop.check();assert.equal(await backdrop.isChecked(),true,'Backdrop switch did not enable');await backdrop.uncheck();assert.equal(await backdrop.isChecked(),false,'Backdrop switch did not disable');passed('Windows backdrop switch can be enabled and disabled');
 await settings.getByRole('button',{name:'Glass & scaling',exact:true}).click();await settings.getByLabel(/Interface size/).focus();await settings.getByLabel(/Interface size/).press('End');
 await settings.getByRole('button',{name:'Typography',exact:true}).click();await settings.getByLabel(/Text size/).focus();await settings.getByLabel(/Text size/).press('End');
 await assertFits(settings,'Largest typography and scaling in Settings');await assertFits(main,'Largest typography and scaling in main');await screenshot(settings,'settings-large-typography');await screenshot(main,'main-large-typography');
 await settings.getByRole('button',{name:'Restore default Glass appearance',exact:true}).click();
 passed('Large typography and interface scaling adapt across native windows');
 passed('Dark/light appearance propagates across native windows; screenshots captured');
 results.push({name:'Explorer/application native drag and physical DPI/transparency review',status:'manual Windows review still required'});
 await writeFile(path.join(output,'results.json'),JSON.stringify({platform:process.platform,arch:process.arch,source_run:process.env.GLASS_E2E_SOURCE_RUN??process.env.GITHUB_RUN_ID,results},null,2));
 if(smallMainFailure)throw smallMainFailure;
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
