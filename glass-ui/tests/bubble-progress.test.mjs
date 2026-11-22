import test from 'node:test';import assert from 'node:assert/strict';import {existsSync} from 'node:fs';import {fileURLToPath} from 'node:url';import {chromium} from 'playwright-core';import {createServer} from 'vite';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('bubble vessel clips liquid at the measured percent and uses the selected palette',{skip:!executablePath||!existsSync(executablePath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try{const page=await browser.newPage();await page.goto(server.resolvedUrls.local[0]);const result=await page.evaluate(async()=>{const {default:React}=await import('/node_modules/.vite/deps/react.js');const {default:{createRoot}}=await import('/node_modules/.vite/deps/react-dom_client.js');const {BubbleProgress}=await import('/src/BubbleProgress.tsx');const host=document.createElement('div');document.body.append(host);const root=createRoot(host);const values=[];for(const percent of [0,64,100]){root.render(React.createElement(BubbleProgress,{percent,colors:['#ff1100','#22ff00','#3344ff'],active:false}));await new Promise(r=>setTimeout(r,30));const svg=host.querySelector('svg');values.push({width:svg.querySelector('clipPath[id$="fill"] rect').getAttribute('width'),colors:[...svg.querySelectorAll('linearGradient[id$="color"] stop')].map(x=>x.getAttribute('stop-color')),outline:svg.querySelector('clipPath[id$="outline"] path').getAttribute('d')})}root.unmount();return values});assert.deepEqual(result.map(x=>x.width),['0','640','1000']);assert.deepEqual(result[1].colors,['#ff1100','#22ff00','#3344ff']);assert.ok((result[1].outline.match(/ C/g)||[]).length>=8,'outline contains multiple curved lobes');}finally{await browser.close();await server.close()}
});
test('Bubble keeps animated liquid and a transparent surround across backdrop finishes', {skip: !executablePath || !existsSync(executablePath)}, async () => {
  const server = await createServer({configFile: false, root: fileURLToPath(new URL('..', import.meta.url)), server: {host: '127.0.0.1', port: 0}, logLevel: 'silent'});
  await server.listen();
  const browser = await chromium.launch({headless: true, executablePath, args: ['--no-sandbox']});
  try {
    const page = await browser.newPage({reducedMotion: 'no-preference'});
    await page.addInitScript(() => {
      localStorage.setItem('mh-glass-progress-shape', 'bubble');
      localStorage.setItem('mh-glass-progress-material', 'liquid-glass');
      localStorage.setItem('mh-glass-track-color', 'palette:arctic');
      localStorage.setItem('mh-glass-track-finish', 'recessed');
      window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {unregisterListener() {}};
      window.__TAURI_INTERNALS__ = {
        metadata: {currentWindow: {label: 'settings'}, currentWebview: {label: 'settings'}},
        transformCallback: () => 1,
        unregisterCallback() {},
        invoke: async command => command === 'glass_settings' ? {} : null,
      };
    });
    await page.goto(`${server.resolvedUrls.local[0]}?settings=1&tab=Appearance`);
    await page.getByRole('button', {name: 'Indicators', exact: true}).click();
    const track = page.locator('.cg-card-preview .cg-bubble-track:visible').first();
    const canvas = track.locator('.cg-liquid-progress');
    await canvas.waitFor();
    const animation = await canvas.evaluate(async element => {
      const context = element.getContext('2d');
      const row = ratio => context.getImageData(0, Math.floor(element.height * ratio), element.width, 1).data;
      const hasLiquid = () => row(.5)[Math.floor(element.width * .25) * 4 + 3] > 0;
      const deadline = performance.now() + 3000;
      while (!hasLiquid() && performance.now() < deadline) await new Promise(requestAnimationFrame);
      const filled = hasLiquid();
      const uncovered = row(.5)[Math.floor(element.width * .85) * 4 + 3] === 0;
      const previous = row(.3).join(',');
      let moved = false;
      while (!moved && performance.now() < deadline) {
        await new Promise(requestAnimationFrame);
        moved = previous !== row(.3).join(',');
      }
      return {filled, uncovered, moved};
    });
    assert.deepEqual(animation, {filled: true, uncovered: true, moved: true});
    const backdrop = page.locator('.cg-indicator-card').filter({has: page.getByText('Progress backdrop', {exact: true})});
    const finish = backdrop.locator('select').first();
    for (const option of ['recessed', 'frosted', 'clear', 'default']) {
      await finish.selectOption(option);
      const surface = await track.evaluate(element => {
        const {backgroundColor, backgroundImage, boxShadow} = getComputedStyle(element);
        const tintStop = element.querySelector('linearGradient[id$="tint"] stop');
        return {backgroundColor, backgroundImage, boxShadow, tint: tintStop.getAttribute('stop-color')};
      });
      assert.equal(surface.backgroundColor, 'rgba(0, 0, 0, 0)');
      assert.equal(surface.backgroundImage, 'none');
      assert.equal(surface.boxShadow, 'none');
      assert.equal(surface.tint, '#a4ffff');
    }
  } finally {
    await browser.close();
    await server.close();
  }
});

test('Bubble takes about half the progress width and reserves enough height for nearby indicators', {skip: !executablePath || !existsSync(executablePath)}, async () => {
  const server = await createServer({configFile: false, root: fileURLToPath(new URL('..', import.meta.url)), server: {host: '127.0.0.1', port: 0}, logLevel: 'silent'});
  await server.listen();
  const browser = await chromium.launch({headless: true, executablePath, args: ['--no-sandbox']});
  try {
    const page = await browser.newPage({viewport: {width: 960, height: 720}, reducedMotion: 'reduce'});
    await page.addInitScript(() => {
      if (!localStorage.getItem('mh-glass-progress-shape')) localStorage.setItem('mh-glass-progress-shape', 'bubble');
      localStorage.setItem('auralis-browser-guide-seen', '1');
      const label = location.search.includes('detail=') ? 'download-1' : 'main';
      const file = {id: 1, file: 'sample.zip', url: 'https://example.org/sample.zip', path: 'C:\\Downloads\\sample.zip', status: 'Downloading', size: 100, downloaded: 64, speed: 10, category: 'Compressed'};
      const visual = {id: 1, active_connections: 1, resumable: true, segments: [{start: 0, cursor: 64, end: 100, worker: 0}], connections: [{id: 0, downloaded: 64, speed: 10, state: 'Receiving'}]};
      window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {unregisterListener() {}};
      window.__TAURI_INTERNALS__ = {
        metadata: {currentWindow: {label}, currentWebview: {label}},
        transformCallback: () => 1,
        unregisterCallback: () => {},
        invoke: async command => {
          if (command === 'dashboard_snapshot') return {downloads: [file], queues: [], categories: [], speed: 10};
          if (command === 'dashboard_visuals') return {downloads: [visual]};
          return null;
        },
      };
    });
    const url = server.resolvedUrls.local[0];
    for (const [route, trackSelector, nextSelector, expectedHeight] of [
      ['', '.cg-row-progress .cg-bubble-track', '.cg-row-progress .cg-chunks', 26],
      ['?detail=1', '.cg-progress-tube .cg-bubble-track', '.cg-indicator-row', 36],
    ]) {
      await page.goto(url + route);
      const track = page.locator(trackSelector);
      await track.waitFor();
      for (const width of [960, 520]) {
        await page.setViewportSize({width, height: 720});
        const {ratio, height, separated, labelFits, withinWrap} = await track.evaluate((element, nextSelector) => {
          const wrap = element.parentElement.getBoundingClientRect();
          const vessel = element.getBoundingClientRect();
          const label = element.nextElementSibling.getBoundingClientRect();
          const next = document.querySelector(nextSelector).getBoundingClientRect();
          return {
            ratio: vessel.width / wrap.width,
            height: parseFloat(getComputedStyle(element).height),
            separated: vessel.bottom + 2 <= next.top + 1,
            labelFits: label.left > vessel.right && label.right <= wrap.right + 1 && element.nextElementSibling.textContent === '64%',
            withinWrap: vessel.top >= wrap.top && vessel.bottom <= wrap.bottom,
          };
        }, nextSelector);
        assert.ok(ratio >= .4 && ratio <= (width >= 960 ? .58 : .74), `Unexpected Bubble width ratio ${ratio} in ${route || 'main'}`);
        assert.ok(Math.abs(height - expectedHeight) < .25);
        assert.ok(separated && labelFits && withinWrap, `Bubble layout collision in ${route || 'main'} at ${width}px`);
      }
    }
    await page.evaluate(() => localStorage.setItem('mh-glass-progress-shape', 'rounded'));
    await page.reload();
    const fullTrack = page.locator('.cg-overall .cg-percent-track');
    await fullTrack.waitFor();
    assert.ok(await fullTrack.evaluate(element => element.clientWidth > element.parentElement.clientWidth * .8));
    assert.ok(await fullTrack.evaluate(element => Math.abs(parseFloat(getComputedStyle(element).height) - 24) < .25));
  } finally {
    await browser.close();
    await server.close();
  }
});
