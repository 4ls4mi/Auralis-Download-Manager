import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('crystalline themes tint the frosted material and keep readable text',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{const page=await browser.newPage({viewport:{width:1200,height:800}});await page.addInitScript(()=>{localStorage.setItem('mh-glass-material','frosted-water-351');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},invoke:async c=>c==='glass_settings'?{}:null,transformCallback:()=>1,unregisterCallback:()=>{}}});await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Appearance');await page.getByRole('button',{name:'Glacier Blue Ice'}).waitFor();assert.equal(await page.getByRole('button',{name:'Light solid'}).count(),0);assert.equal(await page.getByRole('button',{name:'Dark solid'}).count(),0);
 const samples=[];for(const name of ['Glacier Blue Ice','Amethyst Ice','Emerald Frost','Rose Quartz Ice','Amber Crystal','Obsidian Aurora']){await page.getByRole('button',{name}).click();await page.waitForTimeout(250);samples.push(await page.evaluate(()=>{const host=document.querySelector('.cg-window'),canvas=document.querySelector('.cg-frost-canvas'),gl=canvas.getContext('webgl'),program=gl.getParameter(gl.CURRENT_PROGRAM);return {glass:getComputedStyle(host).getPropertyValue('--glass').trim(),ink:getComputedStyle(document.querySelector('.cg-settings-body h2')).color,pixel:Array.from(gl.getUniform(program,gl.getUniformLocation(program,'themeTint')))}}));}
 assert.equal(new Set(samples.map(x=>x.glass)).size,6);assert.ok(samples.every(x=>x.ink==='rgb(255, 255, 255)'));assert.ok(new Set(samples.map(x=>x.pixel.slice(0,3).join(','))).size>=4,'rendered frosted surface should change with theme');await page.close();
 }finally{await browser.close();await server.close()}
});
