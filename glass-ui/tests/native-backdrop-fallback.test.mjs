import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('frosted material falls back to native blur when acrylic fails',{skip:!executablePath||!existsSync(executablePath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try{const page=await browser.newPage();await page.addInitScript(()=>{
  localStorage.setItem('mh-glass-material','frosted-water-351');localStorage.setItem('mh-glass-back-main','desktop');window.effectCalls=[];
  window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   if(cmd==='plugin:window|set_effects'){const effect=args.value?.effects?.[0]??'clear';window.effectCalls.push(effect);if(effect==='acrylic')throw Error('unsupported');return null}
   if(cmd==='dashboard_snapshot')return {downloads:[],queues:[],categories:[],speed:0};if(cmd==='dashboard_visuals')return {downloads:[]};if(cmd==='glass_update_check')return {state:'latest'};return null;
  }};
 });await page.goto(server.resolvedUrls.local[0]);await page.waitForFunction(()=>window.effectCalls.includes('blur'));const calls=await page.evaluate(()=>window.effectCalls);assert.deepEqual(calls.slice(0,2),['acrylic','blur']);assert.equal(await page.getByText('Windows backdrop blur is unavailable; transparent glass is being used.').count(),0)}finally{await browser.close();await server.close()}
});
test('a slow older backdrop request cannot override a newer material',{skip:!executablePath||!existsSync(executablePath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try{const page=await browser.newPage();await page.addInitScript(()=>{
  localStorage.setItem('mh-glass-material','frosted-water-351');localStorage.setItem('mh-glass-back-details','desktop');window.effectCalls=[];window.releaseBackdrop=null;
  window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
  window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{
   if(cmd==='plugin:window|set_effects'){const effect=args.value?.effects?.[0]??'clear';window.effectCalls.push(effect);if(effect==='acrylic'&&!window.releaseBackdrop)await new Promise(resolve=>window.releaseBackdrop=resolve);return null}
   if(cmd==='glass_settings')return {};if(cmd==='glass_tool')return {tools:[],job:null};if(cmd==='dashboard_snapshot')return {downloads:[],queues:[],categories:[],speed:0};return null;
  }};
 });await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Appearance');await page.waitForFunction(()=>Boolean(window.releaseBackdrop));await page.getByRole('button',{name:'Window Glass',exact:true}).click();await page.evaluate(()=>window.releaseBackdrop());await page.waitForFunction(()=>window.effectCalls.at(-1)==='clear');assert.deepEqual(await page.evaluate(()=>window.effectCalls),['acrylic','clear'])}finally{await browser.close();await server.close()}
});
test('desktop glass leaves more of the native backdrop visible than wallpaper mode',{skip:!executablePath||!existsSync(executablePath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try{const page=await browser.newPage();await page.addInitScript(()=>{localStorage.setItem('mh-glass-material','frosted-water-351');if(!sessionStorage.getItem('testedBackdrop')){localStorage.setItem('mh-glass-back-details','desktop');sessionStorage.setItem('testedBackdrop','1')}window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async cmd=>cmd==='glass_settings'?{}:cmd==='dashboard_snapshot'?{downloads:[],queues:[],categories:[],speed:0}:cmd==='glass_tool'?{tools:[],job:null}:null}});await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Appearance');const shell=page.locator('.cg-window.cg-mode-desktop');await shell.waitFor();const opacity=await shell.evaluate(el=>Number(getComputedStyle(el).getPropertyValue('--panel-opacity')));assert.ok(opacity>0&&opacity<0.5,`desktop glass opacity: ${opacity}`);await page.evaluate(()=>{localStorage.setItem('mh-glass-back-details','wallpaper')});await page.reload();const wallpaper=page.locator('.cg-window.cg-mode-wallpaper');await wallpaper.waitFor();const wallpaperOpacity=await wallpaper.evaluate(el=>Number(getComputedStyle(el).getPropertyValue('--panel-opacity')));assert.ok(wallpaperOpacity>opacity,`${wallpaperOpacity} must be greater than ${opacity}`)}finally{await browser.close();await server.close()}
});
