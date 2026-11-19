import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('background update appears even when engine startup fails, respects reminders and shows changelog', {skip:!browserPath||!existsSync(browserPath)}, async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{
  const url=server.resolvedUrls.local[0];
  async function pageFor(snoozeVersion){
   const page=await browser.newPage();
   await page.addInitScript(({snoozeVersion})=>{
    window.calls=[];window.notices=[];window.intervals=[];window.callbacks={};window.eventHandlers={};window.callbackId=0;window.socketUrls=[];window.WebSocket=class {constructor(url){window.socketUrls.push(url)} close(){}};const originalSetInterval=window.setInterval;window.setInterval=(fn,delay,...args)=>{window.intervals.push(delay);return originalSetInterval(fn,delay,...args)};localStorage.setItem('auralis-browser-guide-seen','1');
    if(snoozeVersion){localStorage.setItem('auralis-update-snooze',String(Date.now()+3600000));localStorage.setItem('auralis-update-snooze-version',snoozeVersion)}
    class FakeNotification {static permission='granted';constructor(title,options){window.notices.push({title,body:options.body})}}
    window.Notification=FakeNotification;
    window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
    window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:fn=>{const id=++window.callbackId;window.callbacks[id]=fn;return id},unregisterCallback:()=>{},invoke:async(cmd,args)=>{window.calls.push({cmd,args});if(cmd==='plugin:event|listen'){window.eventHandlers[args.event]=window.callbacks[args.handler];return 1}if(cmd==='glass_update_download'){if(window.failUpdate)throw Error('Download failed');return new Promise(resolve=>{window.resolveDownload=resolve})}if(cmd==='boot_engine')throw Error('Engine unavailable');if(cmd==='glass_update_check')return {state:'available',version:'1.2.3',notes:'Changes in the new release'};if(cmd==='dashboard_snapshot')return {downloads:[],speed:0,queues:[],categories:[]};return null}};
   },{snoozeVersion});
   await page.goto(url);await page.waitForFunction(()=>window.calls.some(c=>c.cmd==='glass_update_check'));await page.waitForTimeout(250);return page;
  }
  const fresh=await pageFor(null);
  assert.ok(await fresh.evaluate(()=>window.calls.some(c=>c.cmd==='open_glass_window'&&c.args.label==='tool-update-toast')),'update window should open even when engine fails');
  assert.equal(await fresh.evaluate(()=>window.notices.length),1,'system notification should be sent once');
  assert.equal(await fresh.evaluate(()=>window.intervals.includes(300000)),false,'push must not use five-minute polling');
  assert.ok(await fresh.evaluate(()=>window.socketUrls.includes('wss://auralis-release-push.auralis-updates.workers.dev/events')),'connect to the release signal');
  assert.match(await fresh.locator('.cg-update-notice').innerText(),/1\.2\.3/);
  await fresh.close();
  const snoozed=await pageFor('1.2.3');
  assert.equal(await snoozed.evaluate(()=>window.calls.some(c=>c.cmd==='open_glass_window'&&c.args.label==='tool-update-toast')),false,'same version reminder should stay snoozed');
  await snoozed.close();
  const newer=await pageFor('1.2.2');
  assert.ok(await newer.evaluate(()=>window.calls.some(c=>c.cmd==='open_glass_window'&&c.args.label==='tool-update-toast')),'a newer version must not inherit an older version snooze');
  await newer.goto(url+'?tool=update-notice');await newer.waitForSelector('.cg-update-changelog');
  assert.match(await newer.locator('.cg-update-changelog').innerText(),/Changes in the new release/);
  await newer.getByRole('button',{name:'Download and install'}).click();
  await newer.waitForFunction(()=>window.resolveDownload&&window.eventHandlers['auralis-update-progress']);
  await newer.evaluate(()=>window.eventHandlers['auralis-update-progress']({payload:{phase:'downloading',downloaded:50,total:100}}));
  await newer.getByRole('progressbar',{name:'Update download progress'}).waitFor();
  assert.equal(await newer.getByRole('progressbar').getAttribute('value'),'50');
  assert.equal(await newer.evaluate(()=>window.calls.some(c=>c.cmd==='glass_update_install')),false,'installation must wait for download');
  await newer.evaluate(()=>window.resolveDownload());
  await newer.waitForFunction(()=>window.calls.some(c=>c.cmd==='glass_update_install'));
  assert.ok(await newer.evaluate(()=>window.calls.findIndex(c=>c.cmd==='glass_update_download') < window.calls.findIndex(c=>c.cmd==='glass_update_install')),'install starts only after downloading');
  await newer.close();
  const failure=await pageFor(null);await failure.goto(url+'?tool=update-notice');await failure.waitForSelector('.cg-update-changelog');await failure.evaluate(()=>{window.failUpdate=true});await failure.getByRole('button',{name:'Download and install'}).click();await failure.getByRole('alert').waitFor();assert.match(await failure.getByRole('alert').innerText(),/Download failed/);assert.equal(await failure.evaluate(()=>window.calls.some(c=>c.cmd==='glass_update_install')),false,'failed downloads must not launch the installer');await failure.close();
 }finally{await browser.close();await server.close()}
});
