import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('WinUI host receives material and theme changes from appearance settings',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{localStorage.setItem('mh-glass-theme','white-frost');localStorage.setItem('mh-glass-material','frosted-water-351');window.appearanceCalls=[];window.__AURALIS_WINUI__={setAppearance:async value=>{window.appearanceCalls.push(value)}};window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async cmd=>cmd==='glass_settings'?{}:null}});
  await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Appearance');
  await page.waitForFunction(()=>window.appearanceCalls?.some(x=>x.material==='frosted-water-351'&&x.light===true));
  await page.getByRole('button',{name:'Window Glass',exact:true}).click();
  await page.waitForFunction(()=>window.appearanceCalls?.some(x=>x.material==='window-glass'&&x.finish==='clear'&&x.tint.join(',')==='245,250,255'));
 }finally{await browser.close();await server.close()}
});
