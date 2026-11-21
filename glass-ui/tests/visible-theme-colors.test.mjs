import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('white and black themes color title bars and text across materials',{skip:!executablePath||!existsSync(executablePath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{const page=await browser.newPage();await page.addInitScript(()=>{localStorage.setItem('auralis-browser-guide-seen','1');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async cmd=>cmd==='dashboard_snapshot'?{downloads:[],queues:[],categories:[],speed:0}:cmd==='dashboard_visuals'?{downloads:[]}:cmd==='glass_update_check'?{state:'latest'}:null}});
 for(const material of ['frosted-water-351','window-glass','builtin-smoked-glass']){
  const values={};for(const theme of ['black-onyx','white-frost','rose']){await page.goto(server.resolvedUrls.local[0]);await page.evaluate(({theme,material})=>{localStorage.setItem('mh-glass-theme',theme);localStorage.setItem('mh-glass-material',material)},{theme,material});await page.reload();await page.waitForSelector('.cg-window-top');values[theme]=await page.evaluate(()=>{const root=document.querySelector('.cg-window'),title=root.querySelector('.cg-window-top');return {light:root.classList.contains('cg-light'),background:getComputedStyle(title).backgroundColor,color:getComputedStyle(title).color,glass:getComputedStyle(root).getPropertyValue('--glass').trim()}})}
  assert.equal(values['white-frost'].light,true);assert.equal(values['black-onyx'].light,false);assert.notEqual(values['white-frost'].background,values['black-onyx'].background);assert.notEqual(values.rose.background,values['black-onyx'].background);assert.notEqual(values['white-frost'].color,values['black-onyx'].color);
 }
 }finally{await browser.close();await server.close()}
});
