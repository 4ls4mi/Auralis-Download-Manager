import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('saved-data check reports changed and unhashed bytes without claiming repair',{skip:!executablePath||!existsSync(executablePath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try{const page=await browser.newPage();await page.addInitScript(()=>{
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
 await page.goto(server.resolvedUrls.local[0]+'?detail=7');
 await page.getByRole('button',{name:'Check saved data'}).click();
 await page.getByText(/1 changed range found; saved data was kept and resume is blocked/).waitFor();
 assert.match(await page.locator('main').innerText(),/has no saved hash and could not be checked/);
 assert.match(await page.locator('main').innerText(),/Local hashes do not prove/);
 assert.equal(await page.getByRole('button',{name:'Resume'}).isDisabled(),true);
 assert.ok(await page.evaluate(()=>window.calls.some(c=>c.cmd==='file_operation'&&c.args.operation==='check-saved')));
 }finally{await browser.close();await server.close()}
});
