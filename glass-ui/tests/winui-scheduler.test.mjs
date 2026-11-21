import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executable=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('WinUI scheduler edits the isolated queue without exposing computer actions',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();page.setDefaultTimeout(5000);
  await page.addInitScript(()=>{let listener;window.requests=[];window.chrome={webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:message=>{
   window.requests.push(message);let value={applied:true};
   if(message.command==='queue_schedules')value={queues:[{name:'Main download queue',files_at_once:1,items:[],sync:false,schedule:{start_on_startup:false,start_at:null,days:[true,true,true,true,true,true,true],stop_at:null,retries:null,once:null,open_when_done:null,hang_up:false,exit_when_done:false,turn_off:null,force_close:false,wake:false}}]};
   else if(message.command==='save_schedule')value={ok:true};
   else if(message.command==='window_is_maximized')value=false;
   else if(message.command==='window_current_monitor')value=null;
   else if(message.command==='window_outer_position')value={x:0,y:0};
   else if(message.command==='window_outer_size')value={width:860,height:660};
   queueMicrotask(()=>listener({data:{id:message.id,ok:true,value}}));
  }}}});
  await page.addInitScript({content:readFileSync(new URL('../../winui-shell/webview/sandbox-compat.js',import.meta.url),'utf8')});
  await page.goto(server.resolvedUrls.local[0]+'?schedule=1');
  await page.getByLabel('Download files at the same time').fill('2');
  await page.getByRole('button',{name:'Save schedule'}).click();
  await page.getByText('Schedule saved.').waitFor();
  const saved=await page.evaluate(()=>window.requests.find(m=>m.command==='save_schedule'));
  assert.equal(saved.payload.name,'Main download queue');assert.equal(saved.payload.files_at_once,2);assert.equal(saved.payload.schedule.wake,false);
  await page.getByRole('button',{name:'Completion',exact:true}).click();
  await page.getByText('Computer and completion actions are unavailable in the development preview.').waitFor();
  assert.equal(await page.getByText('Force applications to close').count(),0);
 }finally{await browser.close();await server.close()}
});
