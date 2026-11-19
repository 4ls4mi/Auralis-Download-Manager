import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {chromium} from 'playwright-core';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('lost connection stays red behind its progress for each backdrop finish', {skip:!executablePath||!existsSync(executablePath)}, async()=>{
 const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try {
  const page=await browser.newPage();
  await page.setContent('<div class="cg-window"><div id="map" class="cg-chunk-map"><span class="lost" style="height:40px;width:40px"><i style="height:40%;background:blue"></i></span></div></div>');
  await page.addStyleTag({content:readFileSync(new URL('../src/ice-crystal.css',import.meta.url),'utf8')});
  await page.addStyleTag({content:'.cg-chunk-map { display: grid; } .cg-chunk-map>span>i { transition: none !important; }'});
  for(const mode of ['cg-fixed-connections','compact'])for(const finish of ['clear','frosted','recessed'])for(const palette of ['', 'cg-palette-track']){
   const result=await page.evaluate(({mode,finish,palette})=>{const m=document.querySelector('#map');m.className=`cg-chunk-map ${mode} cg-connection-track-${finish} ${palette}`;const cell=m.firstElementChild,fill=cell.firstElementChild;return {background:getComputedStyle(cell).backgroundColor,image:getComputedStyle(cell).backgroundImage,height:fill.getBoundingClientRect().height,fill:getComputedStyle(fill).backgroundColor}}, {mode,finish,palette});
   assert.equal(result.background,'rgb(225, 61, 80)');assert.equal(result.image,'none');assert.equal(result.fill,'rgb(0, 0, 255)');assert.ok(result.height>0);
  }
 } finally {await browser.close()}
});
