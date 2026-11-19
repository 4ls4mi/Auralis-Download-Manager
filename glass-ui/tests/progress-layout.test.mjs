import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('download progress controls stay separate when scaled and resized',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{for(const material of ['frosted-water-351','brushed-glass']){
  const page=await browser.newPage({viewport:{width:900,height:600}});
  await page.addInitScript(material=>{localStorage.setItem('mh-glass-material',material);localStorage.setItem('mh-glass-ui-scale','150');const file={id:1,file:'sample.zip',url:'https://example.com/sample.zip',path:'C:\\Downloads\\sample.zip',status:'Downloading',size:100000,downloaded:40000,speed:3400,category:'Compressed'};const visual={id:1,chunk_count:8,active_connections:8,resumable:true,segments:Array.from({length:8},(_,i)=>({start:0,cursor:40+i*3,end:100,worker:i})),connections:Array.from({length:8},(_,i)=>({id:i,downloaded:5000,speed:400,state:'Receiving'})),server:{country_code:'DE',rtt_ms:91,place:{name:'Germany'}}};window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'download-1'},currentWebview:{label:'download-1'}},invoke:async c=>c==='dashboard_snapshot'?{downloads:[file],queues:[],categories:[],speed:3400}:c==='dashboard_visuals'?{downloads:[visual]}:c==='file_operation'?{own_limit_kb:null,is_torrent:false}:null,transformCallback:()=>1,unregisterCallback:()=>{}}},material);
  await page.goto(server.resolvedUrls.local[0]+'?detail=1');await page.waitForSelector('.cg-fixed-connections');
  for(const viewport of [{width:900,height:600},{width:1400,height:900},{width:700,height:460}]){
   await page.setViewportSize(viewport);await page.waitForTimeout(350);
   const bounds=await page.evaluate(()=>{const box=s=>{const r=document.querySelector(s).getBoundingClientRect();return {top:r.top,bottom:r.bottom,left:r.left,right:r.right}};return {scale:parseFloat(getComputedStyle(document.querySelector('.cg-fit-content')).zoom),row:box('.cg-indicator-row'),progress:box('.cg-progress-combined'),graph:box('.cg-compact-speed .cg-graph'),connections:box('.cg-selected-chunks'),blocks:box('.cg-fixed-connections'),actions:box('.cg-bottom-actions'),count:document.querySelectorAll('.cg-fixed-connections>span').length}});
   assert.equal(bounds.count,32);assert.ok(bounds.scale>=1.45,`${material} should preserve requested scale`);assert.ok(bounds.row.bottom<=bounds.actions.top+1,`${material}: row overlaps buttons`);assert.ok(bounds.graph.bottom<=bounds.progress.bottom+1,`${material}: graph escapes panel`);assert.ok(bounds.blocks.bottom<=bounds.connections.bottom+1,`${material}: connections escape panel`);assert.ok(bounds.progress.right<=bounds.connections.left+1,`${material}: panels overlap`);
   const button=page.getByRole('button',{name:'Cancel'});await button.scrollIntoViewIfNeeded();const visible=await page.evaluate(()=>{const page=document.querySelector('.cg-minimal-progress').getBoundingClientRect();const button=[...document.querySelectorAll('.cg-bottom-actions button')].find(b=>b.textContent.includes('Cancel')).getBoundingClientRect();return button.top>=page.top-1&&button.bottom<=page.bottom+1});assert.ok(visible,`${material}: actions should be reachable by scrolling`);
  }await page.close();
 }}finally{await browser.close();await server.close()}
});
