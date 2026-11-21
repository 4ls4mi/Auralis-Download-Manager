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
  const recovery=page.getByLabel('Recovery after a non-resumable download fails');await recovery.waitFor();
  assert.equal(await recovery.inputValue(),'off');
  assert.match(await recovery.locator('..').innerText(),/filename.*Internet Archive.*peers/is);
  await recovery.selectOption('ask');await page.waitForFunction(()=>window.calls.some(c=>c.cmd==='update_glass_setting'&&c.args.key==='torrent_recovery_mode'&&c.args.value==='ask'));
  await recovery.selectOption('auto');await page.waitForFunction(()=>window.calls.some(c=>c.cmd==='update_glass_setting'&&c.args.value==='auto'));
 }finally{await browser.close();await server.close()}
});
