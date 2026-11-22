import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('Frosted Layers keep desktop acrylic while moving between square floating and maximized frames',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();await page.addInitScript(()=>{
   localStorage.setItem('mh-glass-material','frosted-water-351');localStorage.setItem('mh-glass-back-main','desktop');localStorage.setItem('auralis-browser-guide-seen','1');window.maximized=false;window.effects=[];
   window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
   window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(c,args)=>{
    if(c==='plugin:window|set_effects'){window.effects.push(args.value);return null}
    if(c==='plugin:window|is_maximized')return window.maximized;
    if(c==='plugin:window|outer_position')return {x:40,y:40};
    if(c==='plugin:window|outer_size')return {width:900,height:600};
    if(c==='plugin:window|current_monitor')return null;
    if(c==='dashboard_snapshot')return {downloads:[],queues:[],categories:[],speed:0};
    if(c==='glass_update_check')return {state:'latest'};
    return null;
   }};
  });
  await page.goto(server.resolvedUrls.local[0]);
  await page.waitForFunction(()=>window.effects.at(-1)?.effects?.includes('acrylic'));
  for(const maximize of [true,false]) {
   const previous=await page.evaluate(()=>window.effects.length);
   await page.evaluate(maximize=>{window.maximized=maximize;window.dispatchEvent(new Event('resize'))},maximize);
   await page.waitForFunction(({maximize,previous})=>document.querySelector('.cg-window')?.classList.contains('cg-maximized')===maximize&&window.effects.length>previous,{maximize,previous});
   assert.ok(await page.evaluate(()=>window.effects.at(-1)?.effects?.includes('acrylic')));
  }
  assert.ok(await page.locator('.cg-frost-canvas').isVisible());
 }finally{await browser.close();await server.close()}
});
