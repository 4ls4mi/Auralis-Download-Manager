import { createServer } from 'vite';
import { chromium } from 'playwright-core';
import { existsSync } from 'node:fs';
import assert from 'node:assert/strict';

// Exercise actual texture sampling and displacement on Windows with synthetic
// pixels. No desktop capture or real user data is involved.
const candidates=[`${process.env.PROGRAMFILES}\\Google\\Chrome\\Application\\chrome.exe`,`${process.env['PROGRAMFILES(X86)']}\\Microsoft\\Edge\\Application\\msedge.exe`];
const executablePath=candidates.find(existsSync);if(!executablePath)throw Error('Chrome or Edge is required for the GPU compositor test');
const server=await createServer({server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
let browser;
try{
 browser=await chromium.launch({executablePath,headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage();await page.goto(server.resolvedUrls.local[0]);
 const result=await page.evaluate(async()=>{
  const {DesktopRefraction}=await import('/src/rendering/desktopRefraction.ts');
  const source=document.createElement('canvas');source.width=64;source.height=64;const ctx=source.getContext('2d');
  for(let x=0;x<64;x++){ctx.fillStyle=x%8<4?'#ff0000':'#0000ff';ctx.fillRect(x,0,1,64)}
  const output=document.createElement('canvas');output.width=64;output.height=64;
  const renderer=new DesktopRefraction(output), rect={x:0,y:0,width:64,height:64};
  renderer.draw(source,64,64,rect,'water',0);const gl=output.getContext('webgl');const before=new Uint8Array(64*64*4);gl.readPixels(0,0,64,64,gl.RGBA,gl.UNSIGNED_BYTE,before);
  renderer.draw(source,64,64,rect,'water',10);const after=new Uint8Array(before.length);gl.readPixels(0,0,64,64,gl.RGBA,gl.UNSIGNED_BYTE,after);
  let invalid=false;try{renderer.draw(source,64,64,{x:63,y:0,width:5,height:1},'water',5)}catch{invalid=true}
  renderer.dispose();return {different:before.some((v,i)=>v!==after[i]),nonzero:before.some(v=>v>0),invalid};
 });
 assert.ok(result.nonzero,'Source image was not sampled');assert.ok(result.different,'Refraction did not displace source pixels');assert.ok(result.invalid,'Out-of-bounds capture should be rejected');
 console.log('PASS: GPU backdrop samples and displaces synthetic pixels; invalid coordinates are rejected');
}finally{await browser?.close();await server.close()}
