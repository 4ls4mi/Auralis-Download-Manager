import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('dark and light Aurora materials stay distinct and save across reload', {skip:!executablePath||!existsSync(executablePath)}, async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try {const page=await browser.newPage();await page.addInitScript(()=>{window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async cmd=>cmd==='glass_settings'?{}:null}});
 await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Appearance');
 const styles=[];
 for(const [label,id,kind] of [['Aurora Glass — Dark','builtin-aurora-night','cg-dark'],['Aurora Glass — Light','builtin-aurora-ice','cg-light']]){
  const option=page.getByRole('button',{name:label,exact:false});await option.click();await page.waitForSelector('.cg-material-'+id+'.'+kind,{state:'attached'});
  assert.equal(await page.evaluate(()=>localStorage.getItem('mh-glass-material')),id);
  styles.push(await page.locator('.cg-content').evaluate(el=>getComputedStyle(el).backgroundImage));
  const titleColor=await page.locator('.cg-title').evaluate(el=>getComputedStyle(el).color);const rgb=titleColor.match(/\d+/g).map(Number);assert.ok(kind==='cg-light'?rgb[0]<100:rgb[0]>180,`${label}: ${titleColor}`);
  await page.reload();await page.waitForSelector('.cg-material-'+id+'.'+kind,{state:'attached'});
 }
 assert.notEqual(styles[0],styles[1]);
 } finally {await browser.close();await server.close()}
});
test('Aurora toolbar retains distinct action colors and layered surfaces',{skip:!executablePath||!existsSync(executablePath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try{const page=await browser.newPage();await page.addInitScript(()=>{localStorage.setItem('auralis-browser-guide-seen','1');localStorage.setItem('mh-glass-material','builtin-aurora-night');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async cmd=>{if(cmd==='dashboard_snapshot')return {downloads:[],queues:[],categories:[],speed:0};if(cmd==='dashboard_visuals')return {downloads:[]};return null}}});await page.goto(server.resolvedUrls.local[0]);await page.waitForSelector('.cg-toolbar button[data-action=add] svg');const state=await page.evaluate(()=>{const button=n=>{const b=document.querySelector(`.cg-toolbar button[data-action="${n}"]`);return {tone:getComputedStyle(b).getPropertyValue('--tone').trim(),icon:getComputedStyle(b.querySelector('svg')).color}};return {add:button('add'),settings:button('settings'),shine:getComputedStyle(document.querySelector('.cg-content'),'::before').backgroundImage}});assert.equal(state.add.tone,'#08e979');assert.equal(state.settings.tone,'#b840ff');assert.notEqual(state.add.icon,state.settings.icon);assert.match(state.shine,/radial-gradient/)}finally{await browser.close();await server.close()}
});
