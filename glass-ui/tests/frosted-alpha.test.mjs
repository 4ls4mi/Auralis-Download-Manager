import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('frosted material leaves transparent corners in desktop, wallpaper and solid modes',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{
  for(const mode of ['desktop','wallpaper','solid']){
   const page=await browser.newPage({viewport:{width:900,height:600}});
   await page.addInitScript(mode=>{
    localStorage.setItem('mh-glass-material','frosted-water-351');localStorage.setItem('mh-glass-back-main',mode);localStorage.setItem('auralis-browser-guide-seen','1');
    window.calls=[];window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};
    window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},invoke:async(c,args)=>{window.calls.push({c,args});return c==='dashboard_snapshot'?{downloads:[],speed:0,queues:[],categories:[]}:c==='glass_update_check'?{state:'latest'}:null},transformCallback:()=>1,unregisterCallback:()=>{}};
   },mode);
   await page.goto(server.resolvedUrls.local[0]);
   if(mode!=='desktop')await page.waitForSelector('.cg-frost-mask-ready');
   await page.waitForTimeout(200);
   const png=await page.screenshot({omitBackground:true});
   const samples=await page.evaluate(async data=>{const image=new Image();image.src='data:image/png;base64,'+data;await image.decode();const canvas=document.createElement('canvas');canvas.width=image.width;canvas.height=image.height;const ctx=canvas.getContext('2d');ctx.drawImage(image,0,0);return [[0,0],[20,20],[450,300]].map(([x,y])=>ctx.getImageData(x,y,1,1).data[3])},png.toString('base64'));
   assert.equal(samples[0],0,`${mode}: top-left must be transparent`);
   assert.equal(samples[1],0,`${mode}: outer corner must be transparent`);
   assert.ok(samples[2]>0,`${mode}: the center glass must be visible`);
   if(mode==='wallpaper'){
    const point=await page.evaluate(async()=>{const {frostedResizeDirection}=await import('/src/frostedResize.ts');const host=document.querySelector('.cg-window'),value=host.style.getPropertyValue('--frost-shell-mask');const url=value.match(/url\("?(.*?)"?\)/)?.[1];if(!url)return null;const image=new Image();image.src=url;await image.decode();const c=document.createElement('canvas');c.width=image.width;c.height=image.height;const x=c.getContext('2d');x.drawImage(image,0,0);const data=x.getImageData(0,0,c.width,c.height).data;const r=host.getBoundingClientRect();for(let y=70;y<r.height-70;y+=3)for(let px=0;px<r.width;px+=3){const target=document.elementFromPoint(r.left+px,r.top+y);if(target?.closest('button,input,select,textarea,a,[role="button"],.cg-resize'))continue;if(frostedResizeDirection(data,c.width,c.height,r.width,r.height,px,y)==='West')return {x:r.left+px,y:r.top+y}}return null});
    assert.ok(point,'a visible west edge should be available to resize');
    await page.mouse.move(point.x,point.y);await page.mouse.down();await page.mouse.up();
    assert.ok(await page.evaluate(()=>window.calls.some(c=>c.c==='plugin:window|start_resize_dragging'&&c.args.value==='West')),'dragging a visible edge should invoke resize');
   }
   await page.close();
  }
 }finally{await browser.close();await server.close()}
});
