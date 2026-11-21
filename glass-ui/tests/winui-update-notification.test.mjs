import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executable=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('WinUI always shows an in-app update and presents only the selected extra notice',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  for(const presentation of ['quiet','notify','toast','dialog']){
   const context=await browser.newContext();const page=await context.newPage();
   await page.addInitScript(presentation=>{let listener;window.requests=[];window.chrome={webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:message=>{
    window.requests.push(message);let value={applied:true};
    if(message.command==='app_version')value='0.3.48';
    else if(message.command==='update_check')value={state:'available',version:'0.3.49',notes:'Changes'};
    else if(message.command==='dashboard_snapshot')value={downloads:[],queues:[],categories:[],speed:0};
    else if(message.command==='dashboard_visuals')value={downloads:[]};
    else if(message.command==='glass_settings')value={double_click_open:false,confirm_delete:true,show_progress:true};
    else if(message.command==='window_is_maximized')value=false;
    else if(message.command==='window_current_monitor')value=null;
    else if(message.command==='window_outer_position')value={x:0,y:0};
    else if(message.command==='window_outer_size')value={width:960,height:690};
    else if(message.command==='notify_update')value={shown:true};
    queueMicrotask(()=>listener({data:{id:message.id,ok:true,value}}));
   }}};localStorage.setItem('auralis-update-presentation',presentation);localStorage.setItem('auralis-browser-guide-seen','1');localStorage.setItem('auralis-backup-asked','1');},presentation);
   await page.addInitScript({content:readFileSync(new URL('../../winui-shell/webview/sandbox-compat.js',import.meta.url),'utf8')});
   await page.goto(server.resolvedUrls.local[0]);
   await page.locator('.cg-update-notice').waitFor();
   assert.match(await page.locator('.cg-update-notice').innerText(),/Auralis.*0\.3\.49/);
   if(presentation==='notify')await page.waitForFunction(()=>window.requests.some(message=>message.command==='notify_update'));
   if(presentation==='dialog')await page.waitForFunction(()=>window.requests.some(message=>message.command==='open_glass_window' && message.label==='tool-update-notice'));
   const requests=await page.evaluate(()=>window.requests);
   assert.equal(requests.filter(message=>message.command==='notify_update').length,presentation==='notify'?1:0);
   assert.equal(requests.filter(message=>message.command==='open_glass_window' && message.label==='tool-update-notice').length,presentation==='dialog'?1:0);
   assert.equal(requests.some(message=>message.command==='open_glass_window' && message.label==='tool-update-toast'),presentation==='toast');
   await context.close();
  }
 }finally{await browser.close();await server.close()}
});

test('the development update notice does not offer to install over the released app',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{let listener;window.requests=[];window.chrome={webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:message=>{window.requests.push(message);let value={applied:true};if(message.command==='window_is_maximized')value=false;else if(message.command==='window_current_monitor')value=null;else if(message.command==='window_outer_position')value={x:0,y:0};else if(message.command==='window_outer_size')value={width:680,height:520};queueMicrotask(()=>listener({data:{id:message.id,ok:true,value}}));}}};localStorage.setItem('auralis-update-notice',JSON.stringify({version:'0.3.49',notes:'Changes'}));});
  await page.addInitScript({content:readFileSync(new URL('../../winui-shell/webview/sandbox-compat.js',import.meta.url),'utf8')});
  await page.goto(server.resolvedUrls.local[0]+'?tool=update-notice');
  await page.getByText('Update installation is unavailable in this development preview.').waitFor();
  assert.equal(await page.getByRole('button',{name:'Download and install'}).isDisabled(),true);
  assert.equal(await page.evaluate(()=>window.requests.some(message=>message.command==='glass_update_install')),false);
 }finally{await browser.close();await server.close()}
});
