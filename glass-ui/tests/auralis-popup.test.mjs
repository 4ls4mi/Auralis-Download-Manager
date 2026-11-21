import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {chromium} from 'playwright-core';
const chromiumPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('popup restores hidden video controls and reports failed actions',{skip:!chromiumPath||!existsSync(chromiumPath)},async()=>{
 const browser=await chromium.launch({headless:true,executablePath:chromiumPath,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{
   window.calls=[];window.closedByPopup=false;window.close=()=>{window.closedByPopup=true};
   window.chrome={i18n:{getMessage:k=>k,getUILanguage:()=> 'en'},tabs:{query:async()=>[{id:5,url:'https://www.youtube.com/watch?v=abcdef'}]},storage:{local:{get:async v=>v,set:async()=>{}}},runtime:{getManifest:()=>({permissions:[]}),sendMessage:async m=>{window.calls.push(m);if(m.type==='state')return {connected:true};if(m.type==='video-panel-site')return {ok:true,on:false};if(m.type==='site-excluded')return {excluded:false};if(m.type==='media')return {media:[]};if(m.type==='video-panel-set')return {ok:true};if(m.type==='open-options')return {ok:false};return {ok:true}}}};
  });
  await page.goto('http://localhost.invalid').catch(()=>{});
  const html=readFileSync(new URL('../../auralis-extension/popup.html',import.meta.url),'utf8').replace('<script src="popup.js"></script>','');
  await page.setContent(html);
  await page.addScriptTag({content:readFileSync(new URL('../../auralis-extension/popup.js',import.meta.url),'utf8')});
  await page.waitForSelector('#video-panel-site:not(:disabled)');
  assert.equal(await page.locator('#video-panel-site').isChecked(),false);
  await page.locator('#video-panel-site').check();
  assert.ok((await page.evaluate(()=>window.calls)).some(m=>m.type==='video-panel-set'&&m.on===true&&m.url.includes('youtube.com')));
  assert.equal(await page.locator('#youtube-sign-in').count(),0);
  await page.locator('#options').click();
  assert.match(await page.locator('#action-said').textContent(),/Could not reach Auralis/);
  assert.equal(await page.evaluate(()=>window.closedByPopup),false);
 }finally{await browser.close()}
});
