import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executable=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('WinUI isolated Add URL uses the native bridge and explains its test folder',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{let listener;window.previewMessages=[];window.chrome={webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:message=>{window.previewMessages.push(message);const value=message.command==='clipboard_text'?'https://example.com/from-clipboard.bin':message.command==='add_download'?{pending:true}:message.command==='window_is_maximized'?false:message.command==='window_current_monitor'?null:message.command==='window_outer_position'?{x:0,y:0}:message.command==='window_outer_size'?{width:960,height:690}:{applied:true};queueMicrotask(()=>listener({data:{id:message.id,ok:true,value}}))}}};});
  await page.addInitScript({content:readFileSync(new URL('../../winui-shell/webview/sandbox-compat.js',import.meta.url),'utf8')});
  await page.goto(server.resolvedUrls.local[0]+'?add=url');
  await page.getByText('Test downloads use the isolated temporary folder.').waitFor();
  await page.waitForFunction(()=>window.previewMessages.some(message=>message.command==='clipboard_text'));
  await page.waitForFunction(()=>document.querySelector('input[placeholder=\"https://example.com/file.zip\"]')?.value==='https://example.com/from-clipboard.bin');
  await page.getByPlaceholder('https://example.com/file.zip').fill('https://example.com/test.bin');
  await page.getByRole('button',{name:'Continue',exact:true}).click();
  await page.waitForFunction(()=>window.previewMessages.some(message=>message.command==='add_download'));
  const request=await page.evaluate(()=>window.previewMessages.find(message=>message.command==='add_download'));
  assert.equal(request.url,'https://example.com/test.bin');
  assert.equal(request.later,false);
 }finally{await browser.close();await server.close()}
});
