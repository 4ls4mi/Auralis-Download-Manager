import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executable=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('WinUI visual preview loads the real interface without enabling downloads',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{let listener;window.sendPreviewEvent=payload=>listener({data:payload});window.previewMessages=[];window.chrome={webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:message=>{window.previewMessages.push(message);queueMicrotask(()=>listener({data:{id:message.id,ok:true,value:message.command==='window_is_maximized'?false:message.command==='window_current_monitor'?null:message.command==='window_outer_position'?{x:0,y:0}:message.command==='window_outer_size'?{width:960,height:690}:{applied:true}}}))}}};localStorage.setItem('auralis-browser-guide-seen','1');localStorage.setItem('auralis-backup-asked','1')});
  await page.addInitScript({content:readFileSync(new URL('../../winui-shell/webview/preview-compat.js',import.meta.url),'utf8')});
  await page.goto(server.resolvedUrls.local[0]);
  await page.getByText('No downloads in this view').waitFor();
  await page.waitForFunction(()=>window.previewMessages.some(message=>message.command==='set_native_appearance'));
  assert.equal(await page.evaluate(()=>document.documentElement.dataset.auralisWinuiPreview),'true');
  assert.equal(await page.evaluate(async()=>{try{await window.__TAURI_INTERNALS__.invoke('download_action',{action:'start',ids:[1]});return false}catch{return true}}),true);
  assert.equal(await page.evaluate(()=>window.previewMessages.every(message=>['set_native_appearance','window_is_maximized','window_current_monitor','window_outer_position','window_outer_size'].includes(message.command))),true);
  await page.evaluate(()=>{window.previewResizeCount=0;window.addEventListener('resize',()=>window.previewResizeCount++);window.sendPreviewEvent({event:'window_bounds_changed'});});
  await page.waitForFunction(()=>window.previewResizeCount>0);
  await page.getByRole('button',{name:'Settings',exact:true}).click();
  await page.waitForFunction(()=>window.previewMessages.some(message=>message.command==='open_glass_window' && message.label==='settings'));
  await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Appearance');
  await page.getByRole('button',{name:'Window Glass',exact:true}).click();
  await page.waitForFunction(()=>window.previewMessages.some(message=>message.appearance?.material==='window-glass'));
  assert.equal(await page.locator('.cg-window').evaluate(el=>getComputedStyle(el).getPropertyValue('--native-content-opacity').trim()),'.16');
  await page.getByRole('button',{name:'Frosted Layers',exact:true}).click();
  await page.waitForFunction(()=>window.previewMessages.some(message=>message.appearance?.material==='frosted-water-351'));
  assert.equal(await page.locator('.cg-window').evaluate(el=>getComputedStyle(el).getPropertyValue('--native-content-opacity').trim()),'.35');
 }finally{await browser.close();await server.close()}
});
