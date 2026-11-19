import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('checkboxes select individual and visible downloads and start the selected IDs',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{const page=await browser.newPage();await page.addInitScript(()=>{localStorage.setItem('auralis-browser-guide-seen','1');window.calls=[];const downloads=[1,2,3].map(id=>({id,file:`file-${id}.zip`,url:`https://example.com/${id}`,path:`C:\\Downloads\\${id}.zip`,status:'Stopped',size:100,downloaded:0,speed:0,category:'Compressed',added:null}));window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{window.calls.push({cmd,args});if(cmd==='boot_engine')return 'Ready';if(cmd==='glass_update_check')return {state:'latest'};if(cmd==='dashboard_snapshot')return {downloads,queues:[],categories:[],speed:0};if(cmd==='dashboard_visuals')return {downloads:[]};if(cmd==='download_action')return {done:args.ids,skipped:[]};return null}}});
  await page.goto(server.resolvedUrls.local[0]);await page.getByLabel('Select file-1.zip').check();await page.getByLabel('Select file-3.zip').check();assert.equal(await page.getByLabel('Select all visible downloads').evaluate(e=>e.indeterminate),true);await page.getByRole('button',{name:'Start selected'}).click();await page.waitForFunction(()=>window.calls.some(c=>c.cmd==='download_action'));assert.deepEqual(await page.evaluate(()=>window.calls.find(c=>c.cmd==='download_action').args.ids),[1,3]);
  await page.getByLabel('Select all visible downloads').check();assert.equal(await page.getByLabel('Select file-2.zip').isChecked(),true);await page.getByLabel('Select all visible downloads').uncheck();assert.equal(await page.getByLabel('Select file-1.zip').isChecked(),false);
 }finally{await browser.close();await server.close()}
});
