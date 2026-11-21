import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executable=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('WinUI download menu adds and removes an item from a queue',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();page.setDefaultTimeout(5000);
  await page.addInitScript(()=>{let listener,inQueue=false;window.requests=[];window.chrome={webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:message=>{
   window.requests.push(message);let value={applied:true};
   if(message.command==='dashboard_snapshot')value={downloads:[{id:7,file:'test.zip',status:'Stopped',downloaded:20,size:100,speed:0,category:'general'}],queues:[{name:'Main download queue',running:false,ids:inQueue?[7]:[]}],categories:[],speed:0};
   else if(message.command==='dashboard_visuals')value={downloads:[]};
   else if(message.command==='glass_settings')value={double_click_open:false,confirm_delete:true};
   else if(message.command==='update_check')value={state:'latest'};
   else if(message.command==='app_version')value='0.3.48';
   else if(message.command==='queue_item_add'){inQueue=true;value={ok:true}}
   else if(message.command==='queue_item_remove'){inQueue=false;value={ok:true}}
   else if(message.command==='window_is_maximized')value=false;
   else if(message.command==='window_current_monitor')value=null;
   else if(message.command==='window_outer_position')value={x:0,y:0};
   else if(message.command==='window_outer_size')value={width:960,height:690};
   queueMicrotask(()=>listener({data:{id:message.id,ok:true,value}}));
  }}};localStorage.setItem('auralis-backup-asked','1');localStorage.setItem('auralis-browser-guide-seen','1')});
  await page.addInitScript({content:readFileSync(new URL('../../winui-shell/webview/sandbox-compat.js',import.meta.url),'utf8')});
  await page.goto(server.resolvedUrls.local[0]);
  const item=page.getByRole('group',{name:'Download test.zip'});await item.click({button:'right'});
  await page.getByText('Add to queue',{exact:true}).click();await page.getByRole('button',{name:'Main download queue',exact:true}).last().click();
  await page.waitForFunction(()=>window.requests.some(m=>m.command==='queue_item_add'));
  await page.waitForTimeout(200);
  await item.click({button:'right'});await page.getByRole('button',{name:'Delete from queue'}).click();
  await page.waitForFunction(()=>window.requests.some(m=>m.command==='queue_item_remove'));
  const calls=await page.evaluate(()=>window.requests.filter(m=>m.command==='queue_item_add'||m.command==='queue_item_remove'));
  assert.deepEqual(calls.map(m=>m.command),['queue_item_add','queue_item_remove']);assert.ok(calls.every(m=>m.downloadId===7));
 }finally{await browser.close();await server.close()}
});
