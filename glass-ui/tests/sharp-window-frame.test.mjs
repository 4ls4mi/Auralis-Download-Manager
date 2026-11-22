import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';

const executablePath = process.env.AURALIS_TEST_BROWSER || (process.platform === 'linux' ? '/usr/bin/chromium' : '');
test('settings and main WebViews use square edges across window backgrounds', {skip: !executablePath || !existsSync(executablePath)}, async () => {
  const server = await createServer({configFile: false, root: fileURLToPath(new URL('..', import.meta.url)), server: {host: '127.0.0.1', port: 0}, logLevel: 'silent'});
  await server.listen();
  const browser = await chromium.launch({headless: true, executablePath, args: ['--no-sandbox']});
  try {
    const page = await browser.newPage({viewport: {width: 900, height: 600}});
    await page.addInitScript(() => {
      localStorage.setItem('auralis-browser-guide-seen', '1');
      window.calls = [];
      window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {unregisterListener() {}};
      window.__TAURI_INTERNALS__ = {
        metadata: {currentWindow: {label: 'main'}, currentWebview: {label: 'main'}},
        transformCallback: () => 1,
        unregisterCallback() {},
        invoke: async (command, args) => {
          window.calls.push({command, args});
          if (command === 'dashboard_snapshot') return {downloads: [], speed: 0, queues: [], categories: []};
          if (command === 'dashboard_visuals') return {downloads: []};
          if (command === 'glass_update_check') return {state: 'latest'};
          if (command === 'glass_settings') return {};
          return null;
        },
      };
    });
    const cases = [
      {route: '', material: 'rose-pine', background: 'desktop'},
      {route: '', material: 'frosted-water-351', background: 'wallpaper'},
      {route: '?settings=1&tab=Appearance', material: 'builtin-aurora-ice', background: 'desktop'},
      {route: '?settings=1&tab=Appearance', material: 'rose-pine', background: 'solid'},
    ];
    for (const {route, material, background} of cases) {
      await page.goto(`${server.resolvedUrls.local[0]}${route}`);
      await page.evaluate(({material, background}) => {
        localStorage.setItem('mh-glass-material', material);
        localStorage.setItem('mh-glass-back-main', background);
        localStorage.setItem('mh-glass-back-details', background);
        window.dispatchEvent(new Event('storage'));
      }, {material, background});
      const frame = page.locator(`.cg-window.cg-material-${material}.cg-mode-${background} > .cg-content`);
      const geometry = await frame.evaluate(element => {
        const {inset, borderTopLeftRadius, clipPath} = getComputedStyle(element);
        const backdrop = element.parentElement.querySelector('.cg-wallpaper, .cg-solid');
        return {inset, borderTopLeftRadius, clipPath, backdrop: backdrop && getComputedStyle(backdrop).borderTopLeftRadius};
      });
      assert.deepEqual(geometry, {inset: '0px', borderTopLeftRadius: '0px', clipPath: 'none', backdrop: background === 'desktop' ? null : '0px'});
      await page.mouse.move(2, 300);
      await page.mouse.down();
      await page.mouse.up();
      await page.waitForFunction(() => window.calls.some(({command, args}) => command === 'plugin:window|start_resize_dragging' && args.value === 'West'));
    }
  } finally {
    await browser.close();
    await server.close();
  }
});
