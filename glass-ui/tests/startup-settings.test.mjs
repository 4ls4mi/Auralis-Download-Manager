import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('Windows startup settings save both launch state and window mode, and report errors',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{window.calls=[];window.startup={enabled:false,mode:'minimized'};window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{window.calls.push({cmd,args});if(cmd==='startup_settings')return {...window.startup};if(cmd==='set_startup_settings'){if(window.failStartup)throw Error('registry access denied');window.startup={...args};return {...args}}if(cmd==='glass_settings')return {category_dirs:[]};if(cmd==='dashboard_snapshot')return {queues:[]};if(cmd==='plugin:app|version')return '0.3.23';return null}}});
  await page.goto(server.resolvedUrls.local[0]+'?settings=1');
  const toggle=page.getByRole('checkbox',{name:/Start Auralis with Windows/}),mode=page.getByLabel('When Windows starts');
  await toggle.waitFor();assert.equal(await toggle.isChecked(),false);assert.equal(await mode.inputValue(),'minimized');
  await mode.selectOption('window');await page.waitForFunction(()=>window.startup.mode==='window');
  await toggle.check();await page.waitForFunction(()=>window.startup.enabled===true);assert.equal(await mode.inputValue(),'window');
  await mode.selectOption('minimized');await page.waitForFunction(()=>window.startup.mode==='minimized');
  await page.evaluate(()=>window.failStartup=true);await toggle.click();await page.getByText(/registry access denied/).waitFor();assert.equal(await toggle.isChecked(),true);
 }finally{await browser.close();await server.close()}
});
