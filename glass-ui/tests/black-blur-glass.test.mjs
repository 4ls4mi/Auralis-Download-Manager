import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executable=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('black blur glass stays dark and readable even with a light theme',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();await page.addInitScript(()=>{
   localStorage.setItem('auralis-browser-guide-seen','1');localStorage.setItem('mh-glass-material','builtin-black-glass');localStorage.setItem('mh-glass-theme','white-frost');
   window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
   window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{if(cmd==='glass_settings')return {};if(cmd==='glass_tool')return {tools:[],job:null};if(cmd==='export_theme_file'){window.exportedTheme=JSON.parse(args.contents);return 'theme.json'}return null}};
  });
  await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Appearance');
  const frame=page.locator('.cg-window');await frame.waitFor();
  assert.ok((await frame.getAttribute('class')).includes('cg-material-builtin-black-glass'));
  assert.ok((await frame.getAttribute('class')).includes('cg-dark'));
  const button=page.getByRole('button',{name:/Black Blur Glass/});assert.equal(await button.getAttribute('aria-pressed'),'true');
  const color=await page.getByRole('heading',{name:'Appearance'}).first().evaluate(el=>getComputedStyle(el).color);assert.ok(color.match(/\d+/g).map(Number).slice(0,3).every(v=>v>=180),`Text is readable on black glass: ${color}`);
  const surface=await page.locator('.cg-content').evaluate(el=>({background:getComputedStyle(el).backgroundColor,blur:getComputedStyle(el).backdropFilter}));
  assert.match(surface.background,/rgba\(0, 0, 0, 0\.48\)/);assert.match(surface.blur,/blur\(18px\)/);
  await page.getByRole('button',{name:'Export current theme…'}).click();assert.equal((await page.evaluate(()=>window.exportedTheme)).material,'builtin-black-glass');
 }finally{await browser.close();await server.close()}
});
test('main-window panels leave the desktop visible with black blur glass',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{const page=await browser.newPage();await page.addInitScript(()=>{localStorage.setItem('auralis-browser-guide-seen','1');localStorage.setItem('mh-glass-material','builtin-black-glass');localStorage.setItem('mh-glass-back-main','desktop');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async cmd=>{if(cmd==='dashboard_snapshot')return {downloads:[],queues:[],categories:[],speed:0};if(cmd==='dashboard_visuals')return {downloads:[]};return null}}});await page.goto(server.resolvedUrls.local[0]);await page.waitForSelector('.cg-target-main.cg-mode-desktop .cg-list-panel');const surfaces=await page.evaluate(()=>({root:getComputedStyle(document.querySelector('.cg-content')).backgroundColor,panel:getComputedStyle(document.querySelector('.cg-list-panel')).backgroundColor}));assert.match(surfaces.root,/rgba\(0, 0, 0, 0\.3\)/);assert.match(surfaces.panel,/rgba\(8, 10, 14, 0\.22\)/)}finally{await browser.close();await server.close()}
});
