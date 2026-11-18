import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { chromium } from 'playwright-core';
const chromiumPath = process.env.AURALIS_TEST_BROWSER || (process.platform === 'linux' ? '/usr/bin/chromium' : '');
test('thumbnail control targets its own video and sends selected subtitle', {skip: !chromiumPath || !existsSync(chromiumPath)}, async () => {
  const browser = await chromium.launch({headless:true,executablePath:chromiumPath,args:['--no-sandbox']});
  try {
    const page = await browser.newPage();
    await page.route('https://www.youtube.com/**', route => route.fulfill({contentType:'text/html',body:'<a id="thumbnail" href="/watch?v=abcdef12345" style="position:relative;display:block;width:300px;height:160px;background:#555"></a>'}));
    await page.addInitScript(() => {
      const attach=Element.prototype.attachShadow;
      Element.prototype.attachShadow=function(init){return attach.call(this,{...init,mode:'open'})};
      globalThis.sentMessages=[];
      globalThis.chrome={runtime:{sendMessage:async message=>{globalThis.sentMessages.push(message);return {lookup:{state:'ready',token:'sample',title:'Sample',subtitles:[{code:'en',name:'English'}],choices:[{label:'1080p'},{label:'128 kbps',audio:true}]}}}}};
    });
    await page.goto('https://www.youtube.com/');
    await page.addScriptTag({content:readFileSync(new URL('../../auralis-extension/thumbnail.js',import.meta.url),'utf8')});
    const host=page.locator('#thumbnail > span'); await host.waitFor();
    const box=await host.boundingBox(); await page.mouse.click(box.x+10,box.y+10);
    await page.waitForFunction(()=>document.querySelector('#thumbnail > span')?.shadowRoot?.querySelector('select[aria-label="Subtitles"]'));
    assert.ok(await host.evaluate(e=>[...e.shadowRoot.querySelectorAll('.subtitle-list button')].some(b=>b.textContent.includes('English'))));
    const sections=await host.evaluate(e=>[...e.shadowRoot.querySelectorAll('.menu section')].map(section=>section.textContent));
    assert.ok(sections.some(text=>text.includes('Video')&&text.includes('1080p')));
    assert.ok(sections.some(text=>text.includes('Audio')&&text.includes('128 kbps')));
    assert.ok(sections.some(text=>text.includes('Subtitles')&&text.includes('English')));
    await host.evaluate(e=>{const root=e.shadowRoot;root.querySelector('select[aria-label="Subtitles"]').value='manual:en';[...root.querySelectorAll('.menu button')].find(b=>b.textContent.includes('1080p')).click()});
    await host.evaluate(e=>e.shadowRoot.querySelector('.sign-in').click());
    const sent=await page.evaluate(()=>globalThis.sentMessages);
    assert.ok(sent.some(m=>m.type==='youtube-sign-in'));
    assert.equal(sent[0].url,'https://www.youtube.com/watch?v=abcdef12345');
    assert.deepEqual(sent[1].subs.langs,['en']);
    await page.locator('#thumbnail').evaluate(e=>e.setAttribute('href','/watch?v=zyxwvu98765'));
    await page.waitForTimeout(100);
    assert.equal(await host.count(),1);
  } finally { await browser.close(); }
});
