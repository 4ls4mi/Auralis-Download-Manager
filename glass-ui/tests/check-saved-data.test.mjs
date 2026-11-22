import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {browserFixture} from './browser-fixture.mjs';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
const fixture=browserFixture(executablePath);
test('native shell permits the saved-data operations used by the progress window',()=>{
 const source=readFileSync(new URL('../src-tauri/src/main.rs',import.meta.url),'utf8');
 const whitelist=source.match(/if !matches!\(operation\.as_str\(\),([\s\S]*?)\) \{\s*return Err\("Unsupported file operation"/);
 assert.ok(whitelist,'file operation allowlist must be present');
 for(const operation of ['check-saved','check-saved-result','repair-saved','repair-saved-result','find-recovery-torrents','find-recovery-torrents-result','check-recovery-magnet','check-recovery-torrent-url','start-recovery-torrent','start-recovery-torrent-result','cancel-recovery-torrent'])assert.ok(whitelist[1].includes(`"${operation}"`),`${operation} is blocked by the native shell`);
});
test('saved-data check reports changed and unhashed bytes without claiming repair',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.calls=[];window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   window.calls.push({cmd,args});
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,server:{},resumable:true}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
   if(cmd==='file_operation'&&args.operation==='check-saved')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='check-saved-result')return {complete:true,report:{checked_bytes:40,unhashed_bytes:20,damaged_ranges:[[0,40]]}};
   return null;
  }};
 });
 await page.goto(baseUrl+'?detail=7');
 await page.getByRole('button',{name:'Check saved data'}).click();
 await page.getByText(/1 changed range found; saved data was kept and resume is blocked/).waitFor();
 assert.match(await page.locator('main').innerText(),/has no saved hash and could not be checked/);
 assert.match(await page.locator('main').innerText(),/Local hashes do not prove/);
 assert.equal(await page.getByRole('button',{name:'Resume'}).isDisabled(),true);
 assert.ok(await page.evaluate(()=>window.calls.some(c=>c.cmd==='file_operation'&&c.args.operation==='check-saved')));
});

test('known damaged data remains blocked when the progress window reopens',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,recovery_damaged:true,server:{},resumable:true}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};return null;
  }};
 });await page.goto(baseUrl+'?detail=7');
 await page.getByText(/Saved data was found changed/).waitFor();
 assert.equal(await page.getByRole('button',{name:'Resume'}).isDisabled(),true);
});

test('repair checks the source and enables resume only after preparation succeeds',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.repaired=false;window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,recovery_damaged:!window.repaired,server:{},resumable:true}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
   if(cmd==='file_operation'&&args.operation==='repair-saved')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='repair-saved-result'){window.repaired=true;return {complete:true,report:{retained_bytes:40,unhashed_bytes:0,damaged_ranges:[[0,20]]}}}
   return null;
  }};
 });await page.goto(baseUrl+'?detail=7');
 assert.equal(await page.getByRole('button',{name:'Resume'}).isDisabled(),true);
 await page.getByRole('button',{name:'Check source and repair'}).click();
 await page.getByText(/source was checked/i).waitFor();
 await page.waitForFunction(()=>!document.querySelector('button.cg-neon-mint')?.disabled);
 assert.equal(await page.getByRole('button',{name:'Resume'}).isDisabled(),false);
});

test('repair refusal keeps the saved download blocked',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,recovery_damaged:true,server:{},resumable:false}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
   if(cmd==='file_operation'&&args.operation==='repair-saved')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='repair-saved-result')return {complete:true,failure:'The source did not confirm the same file and byte-range support.'};
   return null;
  }};
 });await page.goto(baseUrl+'?detail=7');
 await page.getByRole('button',{name:'Check source and repair'}).click();
 await page.getByRole('alert').filter({hasText:'The source did not confirm'}).waitFor();
 assert.equal(await page.getByRole('button',{name:'Resume'}).isDisabled(),true);
});

test('torrent search explains disclosure and reports only compared pieces',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.calls=[];window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   window.calls.push({cmd,args});
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,server:{},resumable:false}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='check-recovery-magnet')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='start-recovery-torrent')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='start-recovery-torrent-result')return {complete:true,report:{verified_bytes:40,path:'C:/recovery/file.zip'}};
   if(cmd==='choose_recovery_torrent')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents-result')return {complete:true,searched:3,failed:1,matches:[{candidate:0,file_index:1,info_hash:'0123456789012345678901234567890123456789',title:'Example',path:'file.zip',matching_pieces:2,unavailable_pieces:3}]};
   return null;
  }};
 });await page.goto(baseUrl+'?detail=7');
 await page.getByText('Find a torrent for recovery').click();
 await page.getByText(/Searching sends words from this file’s name to Internet Archive/).waitFor();
 assert.equal(await page.evaluate(()=>window.calls.some(c=>c.args?.operation==='find-recovery-torrents')),false);
 await page.getByRole('button',{name:'Search Internet Archive'}).click();
 await page.getByText(/2 matching pieces · 3 unchecked/).waitFor();
 assert.match(await page.locator('main').innerText(),/a match verifies only the pieces compared/i);
 assert.match(await page.locator('main').innerText(),/checking reads the saved data/i);
 assert.ok(await page.evaluate(()=>window.calls.some(c=>c.args?.operation==='find-recovery-torrents')));
 await page.getByRole('button',{name:'Choose torrent file…'}).click();
 await page.waitForFunction(()=>window.calls.some(c=>c.cmd==='choose_recovery_torrent'));
 await page.getByText(/2 matching pieces · 3 unchecked/).waitFor();
 await page.getByLabel('Magnet or torrent URL').fill('magnet:?xt=urn:btih:0123456789012345678901234567890123456789');
 await page.getByRole('button',{name:'Check link'}).click();
 await page.waitForFunction(()=>window.calls.some(c=>c.args?.operation==='check-recovery-magnet'));
 await page.getByText(/2 matching pieces · 3 unchecked/).waitFor();
 assert.equal(await page.getByRole('button',{name:'Continue with this torrent'}).isDisabled(),true);
 await page.getByRole('checkbox',{name:/the rest of the torrent may differ/}).check();
 await page.getByRole('button',{name:'Continue with this torrent'}).click();
 await page.getByText(/Prepared for torrent recovery/).waitFor();
 assert.ok(await page.evaluate(()=>window.calls.some(c=>c.args?.operation==='start-recovery-torrent')));
 assert.deepEqual(await page.evaluate(()=>JSON.parse(window.calls.find(c=>c.args?.operation==='start-recovery-torrent').args.value)),{candidate:0,file_index:1,info_hash:'0123456789012345678901234567890123456789',accept_partial_match:true});
});

test('torrent lookup distinguishes unavailable candidates from a negative match',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,server:{},resumable:false}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents-result')return {complete:true,searched:2,failed:2,matches:[]};return null;
  }};
 });await page.goto(baseUrl+'?detail=7');
 await page.getByText('Find a torrent for recovery').click();
 await page.getByRole('button',{name:'Search Internet Archive'}).click();
 await page.getByText(/No candidates could be checked/).waitFor();
 assert.doesNotMatch(await page.locator('main').innerText(),/No matching saved pieces found/);
});

test('ordinary-file recovery controls stay hidden for video and multi-file downloads',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'video.mp4',url:'https://example.com/video',path:'C:/video.mp4',status:'Stopped',size:100,downloaded:60,speed:0,category:'Video'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,is_video:true,server:{},resumable:true}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};return null;
  }};
 });await page.goto(baseUrl+'?detail=7');
 await page.getByText('video.mp4').first().waitFor();
 assert.equal(await page.getByText('Find a torrent for recovery').count(),0);
 assert.equal(await page.getByRole('button',{name:'Check saved data'}).count(),0);
});

test('torrent handoff reports failure and does not claim the transfer started',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,server:{},resumable:false}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents-result')return {complete:true,searched:1,failed:0,matches:[{candidate:0,file_index:0,info_hash:'0123456789012345678901234567890123456789',title:'Example',path:'file.zip',matching_pieces:1,unavailable_pieces:2}]};
   if(cmd==='file_operation'&&args.operation==='start-recovery-torrent')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='start-recovery-torrent-result')return {complete:true,failure:'Could not save the recovery state. The original partial was kept.'};return null;
  }};
 });await page.goto(baseUrl+'?detail=7');
 await page.getByText('Find a torrent for recovery').click();await page.getByRole('button',{name:'Search Internet Archive'}).click();
 await page.getByRole('checkbox',{name:/the rest of the torrent may differ/}).check();
 await page.getByRole('button',{name:'Continue with this torrent'}).click();
 await page.getByRole('alert').filter({hasText:'Could not save the recovery state'}).waitFor();
 assert.doesNotMatch(await page.locator('main').innerText(),/Prepared for torrent recovery/);
});

test('a direct-to-torrent handoff remains clearly identified after reopening',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/recovery/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:true,direct_recovery:true,original_partial:'C:/original.bin.part',server:{},resumable:true}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:true};return null;
  }};
 });await page.goto(baseUrl+'?detail=7');
 await page.getByText('Direct download → BitTorrent').waitFor();
 await page.getByText(/The original partial was preserved/).waitFor();
 assert.match(await page.locator('main').innerText(),/C:\/original\.bin\.part/);
 assert.equal(await page.getByText('Find a torrent for recovery').count(),0);
});

test('download list distinguishes ordinary torrents from recovered torrents',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  localStorage.setItem('auralis-browser-guide-seen','1');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd)=>{
   if(cmd==='dashboard_snapshot')return {downloads:[{id:1,file:'direct.zip',url:'https://example.com/file',path:'C:/recovery/direct.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'},{id:2,file:'torrent.zip',url:'magnet:?xt=urn:btih:abc',path:'C:/torrent.zip',status:'Stopped',size:100,downloaded:20,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:1,segments:[],connections:[],is_torrent:true,direct_recovery:true,server:{},resumable:true},{id:2,segments:[],connections:[],is_torrent:true,direct_recovery:false,server:{},resumable:true}]};return null;
  }};
 });await page.goto(baseUrl);
 await page.getByLabel('Direct download continued as torrent').waitFor();
 await page.getByLabel('Torrent download',{exact:true}).waitFor();
});

test('reopening a progress window restores an existing recovery search',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.calls=[];window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   window.calls.push({cmd,args});
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,recovery_search_available:true,server:{},resumable:false}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents-result')return {complete:true,searched:1,failed:0,matches:[{candidate:0,file_index:0,info_hash:'0123456789012345678901234567890123456789',title:'Restored candidate',path:'file.zip',matching_pieces:1,unavailable_pieces:2}]};return null;
  }};
 });await page.goto(baseUrl+'?detail=7');
 await page.getByText(/Restored candidate/).waitFor();
 assert.equal(await page.getByRole('button',{name:'Continue with this torrent'}).isDisabled(),true);
 assert.equal(await page.evaluate(()=>window.calls.some(c=>c.args?.operation==='start-recovery-torrent')),false);
});

test('torrent recovery clearly refuses downloads with an expected whole-file checksum',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,server:{},resumable:false}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false,checksum:'SHA-256:example'};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents-result')return {complete:true,searched:1,failed:0,matches:[{candidate:0,file_index:0,info_hash:'0123456789012345678901234567890123456789',title:'Example',path:'file.zip',matching_pieces:1,unavailable_pieces:2}]};return null;
  }};
 });await page.goto(baseUrl+'?detail=7');await page.getByText('Find a torrent for recovery').click();await page.getByRole('button',{name:'Search Internet Archive'}).click();
 await page.getByText(/unavailable for a file with an expected whole-file checksum/).waitFor();
 assert.equal(await page.getByRole('button',{name:'Continue with this torrent'}).isDisabled(),true);
});

test('cancel during preparation asks the backend to stop the handoff',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.calls=[];window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   window.calls.push({cmd,args});
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,server:{},resumable:false}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents-result')return {complete:true,searched:1,failed:0,matches:[{candidate:0,file_index:0,info_hash:'0123456789012345678901234567890123456789',title:'Example',path:'file.zip',matching_pieces:1,unavailable_pieces:2}]};
   if(cmd==='file_operation'&&args.operation==='start-recovery-torrent')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='start-recovery-torrent-result')return {complete:false};
   if(cmd==='file_operation'&&args.operation==='cancel-recovery-torrent')return {already_started:false};return null;
  }};
 });await page.goto(baseUrl+'?detail=7');await page.getByText('Find a torrent for recovery').click();await page.getByRole('button',{name:'Search Internet Archive'}).click();
 await page.getByRole('checkbox',{name:/the rest of the torrent may differ/}).check();await page.getByRole('button',{name:'Continue with this torrent'}).click();
 await page.getByText(/Rechecking saved pieces before continuing/).waitFor();await page.getByRole('button',{name:'Cancel',exact:true}).click();
 assert.ok(await page.evaluate(()=>window.calls.some(c=>c.args?.operation==='cancel-recovery-torrent')));
});

test('cancel delegates a just-completed handoff to the backend',{skip:!executablePath||!existsSync(executablePath)},async t=>{
 const {page,baseUrl}=await fixture.openPage(t);
 await page.addInitScript(()=>{
  window.calls=[];window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-7'},currentWebview:{label:'download-7'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   window.calls.push({cmd,args});
   if(cmd==='dashboard_snapshot')return {downloads:[{id:7,file:'file.zip',url:'https://example.com/file',path:'C:/file.zip',status:'Stopped',size:100,downloaded:60,speed:0,category:'General'}],queues:[],categories:[],speed:0};
   if(cmd==='dashboard_visuals')return {downloads:[{id:7,segments:[],connections:[],is_torrent:false,server:{},resumable:false}]};
   if(cmd==='file_operation'&&args.operation==='details')return {own_limit_kb:null,is_torrent:false};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='find-recovery-torrents-result')return {complete:true,searched:1,failed:0,matches:[{candidate:0,file_index:0,info_hash:'0123456789012345678901234567890123456789',title:'Example',path:'file.zip',matching_pieces:1,unavailable_pieces:2}]};
   if(cmd==='file_operation'&&args.operation==='start-recovery-torrent')return {pending:true};
   if(cmd==='file_operation'&&args.operation==='start-recovery-torrent-result')return {complete:true,report:{verified_bytes:40,path:'C:/recovery/file.zip'}};
   if(cmd==='file_operation'&&args.operation==='cancel-recovery-torrent')return {already_started:true};return null;
  }};
 });await page.goto(baseUrl+'?detail=7');await page.getByText('Find a torrent for recovery').click();await page.getByRole('button',{name:'Search Internet Archive'}).click();
 await page.getByRole('checkbox',{name:/the rest of the torrent may differ/}).check();await page.getByRole('button',{name:'Continue with this torrent'}).click();
 await page.getByText(/Prepared for torrent recovery/).waitFor();await page.getByRole('button',{name:'Cancel',exact:true}).click();
 assert.ok(await page.evaluate(()=>window.calls.some(c=>c.args?.operation==='cancel-recovery-torrent')));
});
