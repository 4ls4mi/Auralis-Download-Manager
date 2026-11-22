import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('torrent recovery is opt-in and its search and peer disclosure is visible',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();await page.addInitScript(()=>{
   window.calls=[];window.config={torrent_recovery_mode:'off'};
   window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
   window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
    window.calls.push({cmd,args});if(cmd==='glass_settings')return window.config;
    if(cmd==='dashboard_snapshot')return {queues:[]};
    if(cmd==='update_glass_setting'){window.config[args.key]=args.value;return {saved:true}}
    return null;
   }};
  });
  await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Torrents');
  const recovery=page.getByLabel('Torrent recovery after a direct download fails');await recovery.waitFor();
  assert.equal(await recovery.inputValue(),'off');
  assert.match(await recovery.locator('..').innerText(),/filename.*Internet Archive.*peers/is);
  await recovery.selectOption('ask');await page.waitForFunction(()=>window.calls.some(c=>c.cmd==='update_glass_setting'&&c.args.key==='torrent_recovery_mode'&&c.args.value==='ask'));
  await recovery.selectOption('auto');await page.waitForFunction(()=>window.calls.some(c=>c.cmd==='update_glass_setting'&&c.args.value==='auto'));
 }finally{await browser.close();await server.close()}
});

test('an automatic recovery search displays its results in the download window',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();await page.addInitScript(()=>{
   window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
   window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
    if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Error',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
    if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,recovery_search_available:true,recovery_auto_search:true,server:{},resumable:false}]};
    if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
    if(cmd==='file_operation'&&args.operation==='find-recovery-torrents-result')return {complete:true,searched:1,failed:0,matches:[{candidate:0,file_index:0,info_hash:'0'.repeat(40),title:'Matching candidate',path:'file.zip',matching_pieces:2,unavailable_pieces:1}]};
    return null;
   }};
  });
  await page.goto(server.resolvedUrls.local[0]+'?detail=7');
  await page.getByText('Matching candidate', {exact:false}).waitFor({state:'visible'});
  await page.getByText('A possible torrent match is ready for review below.').waitFor({state:'visible'});
  assert.equal(await page.getByRole('button',{name:'Continue with this torrent'}).isDisabled(),true);
 }finally{await browser.close();await server.close()}
});

test('cancel during automatic search asks the backend to prevent handoff',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();await page.addInitScript(()=>{
   window.calls=[];window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
   window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
    window.calls.push({cmd,args});
    if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Error',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
    if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,recovery_search_available:true,recovery_auto_search:true,server:{},resumable:false}]};
    if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
    if(cmd==='file_operation'&&args.operation==='find-recovery-torrents-result')return {complete:false};
    if(cmd==='file_operation'&&args.operation==='cancel-recovery-torrent')return {ok:true,already_started:false};
    return null;
   }};
  });
  await page.goto(server.resolvedUrls.local[0]+'?detail=7');
  await page.getByText(/The direct download failed. Searching/).waitFor();
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  assert.equal(await page.evaluate(()=>window.calls.some(c=>c.args?.operation==='cancel-recovery-torrent')),true);
 }finally{await browser.close();await server.close()}
});

test('manual recovery checks torrent URLs, magnets, and local torrent files after a failed search',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});
 await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{
   window.calls=[];
   window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
   window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
    window.calls.push({cmd,args});
    if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Error',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
    if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,recovery_search_available:true,recovery_auto_search:true,recovery_stage:'no-match',server:{},resumable:false}]};
    if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
    if(cmd==='file_operation'&&args.operation==='find-recovery-torrents-result')return {complete:true,searched:1,failed:0,matches:[]};
    if(cmd==='choose_recovery_torrent')return {pending:true};
    return null;
   }};
  });
  await page.goto(server.resolvedUrls.local[0]+'?detail=7');
  await page.getByText('A matching torrent could not be verified.',{exact:false}).waitFor();
  const field=page.getByLabel('Magnet or torrent URL');
  for(const [value,operation] of [
   ['https://example.org/file.torrent','check-recovery-torrent-url'],
   ['magnet:?xt=urn:btih:0000000000000000000000000000000000000000','check-recovery-magnet']
  ]){
   await field.fill(' '+value+' ');
   await page.getByRole('button',{name:'Check link'}).click();
   await page.waitForFunction(({operation,value})=>window.calls.some(c=>c.args?.operation===operation&&c.args.value===value),{operation,value});
  }
  await page.getByRole('button',{name:'Choose torrent file…'}).click();
  await page.waitForFunction(()=>window.calls.some(c=>c.cmd==='choose_recovery_torrent'&&c.args.id===7));
 }finally{await browser.close();await server.close()}
});

test('a reopened mixed download shows BitTorrent swarm data and its preserved direct partial',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});
 await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{
   window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
   window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
    if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/Recovered/file.zip',status:'Downloading',size:1000,downloaded:600,speed:40,category:'General'}],queues:[],categories:[],speed:40};
    if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:true,direct_recovery:true,original_partial:'C:/file.zip.part',recovery_verified_bytes:320,recovery_direct_error:'The original host refused the range.',recovery_stage:'handed-off',server:{hostname:'example.com'},resumable:true,torrent:{peers:4,uploaded:20,upload_speed:8,info_hash:'a'.repeat(40),selected_files:1}}]};
    if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:true};
    return null;
   }};
  });
  await page.goto(server.resolvedUrls.local[0]+'?detail=7');
  await page.getByRole('heading',{name:'Downloading via BitTorrent'}).waitFor();
  await page.getByText('Direct download → BitTorrent',{exact:true}).waitFor();
  await page.getByText('The original partial was preserved at C:/file.zip.part.',{exact:false}).waitFor();
  await page.getByText('Reused 320 B of verified pieces.',{exact:false}).waitFor();
  await page.getByText('The original host refused the range.',{exact:false}).waitFor();
  const swarm=page.locator('section').filter({has:page.getByRole('heading',{name:'BitTorrent swarm'})});
  assert.match(await swarm.innerText(),/Connected peers\s+4/);
  assert.match(await swarm.innerText(),/Upload speed\s+8 B\/s/);
  assert.equal(await page.getByText('Server',{exact:true}).count(),0);
 }finally{await browser.close();await server.close()}
});

test('the main list alerts when recovery finds a match and when the download switches to peers',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});
 await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{
   window.recoveryStage='matched';
   localStorage.setItem('auralis-browser-guide-seen','1');
   localStorage.setItem('auralis-backup-asked','1');
   window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
   window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd)=>{
    const mixed=window.recoveryStage==='handed-off';
    if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:mixed?'Downloading':'Error',size:1000,downloaded:600,speed:mixed?40:0,category:'General'}],queues:[],categories:[],speed:0};
    if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:mixed,direct_recovery:mixed,recovery_auto_search:!mixed,recovery_stage:window.recoveryStage,recovery_handoff_available:mixed,server:{},resumable:true}]};
    return null;
   }};
  });
  await page.goto(server.resolvedUrls.local[0]);
  const notice=page.getByRole('status').filter({hasText:'Torrent match found'});
  await notice.waitFor();
  await notice.getByRole('button',{name:'Dismiss torrent recovery notice'}).click();
  await notice.waitFor({state:'hidden'});
  await page.getByRole('button',{name:'Review torrent match',exact:true}).waitFor();
  await page.evaluate(()=>{window.recoveryStage='handed-off'});
  await page.getByRole('status').filter({hasText:'Downloading via BitTorrent'}).waitFor();
  await page.getByLabel('Direct download continued as torrent').waitFor();
 }finally{await browser.close();await server.close()}
});
