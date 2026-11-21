import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executable=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('WinUI progress window requests and displays a saved-data check',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{let listener;window.requests=[];window.chrome={webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:message=>{
   window.requests.push(message);let value={applied:true};
   if(message.command==='dashboard_snapshot')value={downloads:[{id:7,file:'test.zip',status:'Stopped',downloaded:20,size:100,speed:0}],queues:[],categories:[],speed:0};
   else if(message.command==='dashboard_visuals')value={downloads:[{id:7,active_connections:0}]};
   else if(message.command==='file_details')value={own_limit_kb:null};
   else if(message.command==='check_saved')value={pending:true};
   else if(message.command==='check_saved_result')value={complete:true,report:{checked_bytes:16,unhashed_bytes:4,damaged_ranges:[]}};
   else if(message.command==='window_is_maximized')value=false;
   else if(message.command==='window_current_monitor')value=null;
   else if(message.command==='window_outer_position')value={x:0,y:0};
   else if(message.command==='window_outer_size')value={width:760,height:560};
   queueMicrotask(()=>listener({data:{id:message.id,ok:true,value}}));
  }}}});
  await page.addInitScript({content:readFileSync(new URL('../../winui-shell/webview/sandbox-compat.js',import.meta.url),'utf8')});
  await page.goto(server.resolvedUrls.local[0]+'?detail=7');
  await page.getByRole('button',{name:'Check saved data'}).click();
  await page.getByText(/No changes detected in checked data/).waitFor();
  const calls=await page.evaluate(()=>window.requests.filter(m=>m.command.startsWith('check_saved')));
  assert.deepEqual(calls.map(m=>m.command),['check_saved','check_saved_result']);
  assert.ok(calls.every(m=>m.downloadId===7 && !('value' in m)));
  assert.match(await page.locator('body').innerText(),/Local hashes do not prove the original download was correct/);
 }finally{await browser.close();await server.close()}
});
