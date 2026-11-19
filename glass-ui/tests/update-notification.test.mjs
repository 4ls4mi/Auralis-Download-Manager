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
    window.calls=[];window.notices=[];window.intervals=[];const originalSetInterval=window.setInterval;window.setInterval=(fn,delay,...args)=>{window.intervals.push(delay);return originalSetInterval(fn,delay,...args)};localStorage.setItem('auralis-browser-guide-seen','1');
    if(snoozeVersion){localStorage.setItem('auralis-update-snooze',String(Date.now()+3600000));localStorage.setItem('auralis-update-snooze-version',snoozeVersion)}
    class FakeNotification {static permission='granted';constructor(title,options){window.notices.push({title,body:options.body})}}
    window.Notification=FakeNotification;
    window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
    window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{window.calls.push({cmd,args});if(cmd==='boot_engine')throw Error('Engine unavailable');if(cmd==='glass_update_check')return {state:'available',version:'1.2.3',notes:'Changes in the new release'};if(cmd==='dashboard_snapshot')return {downloads:[],speed:0,queues:[],categories:[]};return null}};
   },{snoozeVersion});
   await page.goto(url);await page.waitForFunction(()=>window.calls.some(c=>c.cmd==='glass_update_check'));await page.waitForTimeout(250);return page;
  }
  const fresh=await pageFor(null);
  assert.ok(await fresh.evaluate(()=>window.calls.some(c=>c.cmd==='open_glass_window'&&c.args.label==='tool-update-notice')),'update window should open even when engine fails');
  assert.equal(await fresh.evaluate(()=>window.notices.length),1,'system notification should be sent once');
  assert.ok(await fresh.evaluate(()=>window.intervals.includes(300000)),'background checks should run every five minutes');
  assert.match(await fresh.locator('.cg-update-notice').innerText(),/1\.2\.3/);
  await fresh.close();
  const snoozed=await pageFor('1.2.3');
  assert.equal(await snoozed.evaluate(()=>window.calls.some(c=>c.cmd==='open_glass_window'&&c.args.label==='tool-update-notice')),false,'same version reminder should stay snoozed');
  await snoozed.close();
  const newer=await pageFor('1.2.2');
  assert.ok(await newer.evaluate(()=>window.calls.some(c=>c.cmd==='open_glass_window'&&c.args.label==='tool-update-notice')),'a newer version must not inherit an older version snooze');
  await newer.goto(url+'?tool=update-notice');await newer.waitForSelector('.cg-update-changelog');
  assert.match(await newer.locator('.cg-update-changelog').innerText(),/Changes in the new release/);
  await newer.getByRole('button',{name:'Download update'}).click();
  await newer.getByRole('button',{name:'Restart and install'}).waitFor();
  assert.ok(await newer.evaluate(()=>window.calls.some(c=>c.cmd==='glass_update_download')));
  await newer.close();
 }finally{await browser.close();await server.close()}
});
