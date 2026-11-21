import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executable=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('installed WinUI file-info view sends its chosen destination and queue choice',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();page.setDefaultTimeout(15000);
  const setup=()=>{let listener;window.__AURALIS_INSTALLED_HOST__=true;window.requests=[];window.chrome={webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:message=>{
   window.requests.push(message);let value={applied:true};
   if(message.command==='pending_file_info')value={id:7,waiting:0,categories:[{key:'general',name:'General'}],info:{url:'https://example.test/file',save_as:'C:\\Downloads\\file.bin',category:'general',description:'',remember:false,size:100,probing:false,error:null,server:{country_code:null,rtt_ms:null}}};
   else if(message.command==='dashboard_snapshot')value={downloads:[],queues:[],categories:[{key:'general',name:'General'}],speed:0};
   else if(message.command==='glass_settings')value={max_connections:8};
   else if(message.command==='file_info_action')value={ok:true,id:8};
   else if(message.command==='window_is_maximized')value=false;
   else if(message.command==='window_current_monitor')value=null;
   else if(message.command==='window_outer_position')value={x:0,y:0};
   else if(message.command==='window_outer_size')value={width:780,height:560};
   else if(message.command==='window_close')value=null;
   queueMicrotask(()=>listener({data:{id:message.id,ok:true,value}}));
  }}}};
  // Playwright does not guarantee the order of separate init scripts. The
  // installed flag and native mock must exist before the adapter evaluates.
  await page.addInitScript({content:`(${setup.toString()})();\n${readFileSync(new URL('../../winui-shell/webview/sandbox-compat.js',import.meta.url),'utf8')}`});
  await page.goto(server.resolvedUrls.local[0]+'?request=7');
  const path=page.getByLabel('Save As');await path.fill('C:\\Downloads\\renamed.bin');
  await page.getByRole('button',{name:'Download Later'}).click();
  await page.waitForFunction(()=>window.requests.some(m=>m.command==='file_info_action' && m.action==='commit'));
  const request=await page.evaluate(()=>window.requests.find(m=>m.command==='file_info_action' && m.action==='commit'));
  assert.equal(request.downloadId,7);assert.equal(request.payload.save_as,'C:\\Downloads\\renamed.bin');assert.equal(request.payload.later,true);
  assert.equal(await page.evaluate(()=>window.__AURALIS_WINUI__.updateInstallSupported),false);
 }finally{await browser.close();await server.close()}
});
