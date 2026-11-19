import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('download columns resize and retain their width',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{const page=await browser.newPage({viewport:{width:1000,height:700}});await page.addInitScript(()=>{localStorage.setItem('auralis-browser-guide-seen','1');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async c=>c==='dashboard_snapshot'?{downloads:[],queues:[],categories:[],speed:0}:c==='dashboard_visuals'?{downloads:[]}:null}});await page.goto(server.resolvedUrls.local[0]);const separator=page.getByRole('separator',{name:'Resize file name column'});await separator.focus();await page.keyboard.press('ArrowRight');assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('auralis-download-columns'))[0]),230);await page.reload();assert.match(await page.locator('.cg-table').getAttribute('style'),/minmax\(230px/);const labels=await page.locator('.cg-cols > span').allTextContents();assert.deepEqual(labels,['FILE NAME','SIZE','STATUS','PROGRESS','SPEED','TIME LEFT']);}finally{await browser.close();await server.close()}
});
