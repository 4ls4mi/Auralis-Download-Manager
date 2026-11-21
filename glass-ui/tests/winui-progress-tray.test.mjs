import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executable=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('WinUI hidden-download list shows details and requests restoration',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{let listener;window.previewMessages=[];window.chrome={webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:message=>{
   window.previewMessages.push(message);let value={applied:true};
   if(message.command==='progress_ids')value=[7,8];
   else if(message.command==='dashboard_snapshot')value={downloads:[{id:7,file:'one.zip',status:'Downloading',downloaded:50,size:100,speed:5},{id:8,file:'two.zip',status:'Stopped',downloaded:20,size:100,speed:0}],queues:[],categories:[],speed:5};
   else if(message.command==='dashboard_visuals')value={downloads:[{id:7,active_connections:2},{id:8,active_connections:0}]};
   else if(message.command==='window_is_maximized')value=false;
   else if(message.command==='window_current_monitor')value=null;
   else if(message.command==='window_outer_position')value={x:0,y:0};
   else if(message.command==='window_outer_size')value={width:500,height:360};
   else if(message.command==='progress_restore'||message.command==='window_close')value=null;
   queueMicrotask(()=>listener({data:{id:message.id,ok:true,value}}));
  }}};});
  await page.addInitScript({content:readFileSync(new URL('../../winui-shell/webview/sandbox-compat.js',import.meta.url),'utf8')});
  await page.goto(server.resolvedUrls.local[0]+'?tool=progress-tray&x=100&y=100');
  const second=page.getByRole('button',{name:/two\.zip/});await second.waitFor();await second.hover();
  await page.getByText('0 connections',{exact:true}).waitFor();
  await second.click();await page.waitForFunction(()=>window.previewMessages.some(message=>message.command==='progress_restore'));
  assert.equal(await page.evaluate(()=>window.previewMessages.find(message=>message.command==='progress_restore').downloadId),8);
 }finally{await browser.close();await server.close()}
});
