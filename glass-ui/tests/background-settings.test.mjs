import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';

const executablePath = process.env.AURALIS_TEST_BROWSER || (process.platform === 'linux' ? '/usr/bin/chromium' : '');

test('Backgrounds save independent colors and media for main and popup windows with Aurora', {skip: !executablePath || !existsSync(executablePath)}, async () => {
  const server = await createServer({configFile: false, root: fileURLToPath(new URL('..', import.meta.url)), server: {host: '127.0.0.1', port: 0}, logLevel: 'silent'});
  await server.listen();
  const browser = await chromium.launch({headless: true, executablePath, args: ['--no-sandbox']});
  try {
    const context = await browser.newContext({viewport: {width: 1000, height: 750}});
    await context.addInitScript(() => {
      if (!localStorage.getItem('mh-glass-material')) localStorage.setItem('mh-glass-material', 'builtin-aurora-night');
      localStorage.setItem('auralis-browser-guide-seen', '1');
      const label = location.search.includes('settings=') ? 'settings' : 'main';
      window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {unregisterListener() {}};
      window.__TAURI_INTERNALS__ = {
        metadata: {currentWindow: {label}, currentWebview: {label}},
        transformCallback: () => 1,
        unregisterCallback() {},
        convertFileSrc: path => '/fixture-background/' + path.split(/[\\/]/).pop(),
        invoke: async (command, args) => {
          if (command === 'glass_settings') return {};
          if (command === 'dashboard_snapshot') return {downloads: [], speed: 0, queues: [], categories: []};
          if (command === 'dashboard_visuals') return {downloads: []};
          if (command === 'select_wallpaper') return args.target === 'main' ? 'C:\\sample\\main.png' : 'C:\\sample\\popups.mp4';
          return null;
        },
      };
    });
    const main = await context.newPage();
    const settings = await context.newPage();
    const url = server.resolvedUrls.local[0];
    const settingsUrl = `${url}?settings=1&tab=Appearance`;
    await main.goto(url);
    await settings.goto(settingsUrl);
    await settings.getByRole('button', {name: 'Backgrounds', exact: true}).click();
    const mainCard = settings.getByRole('region', {name: 'Main window', exact: true});
    const popupCard = settings.getByRole('region', {name: 'Download and other popups', exact: true});
    const desktop = card => card.getByRole('button', {name: 'Desktop', exact: true});
    const solid = card => card.getByRole('button', {name: 'Solid color', exact: true});
    const media = card => card.getByRole('button', {name: 'Image or video', exact: true});
    const choose = card => card.getByRole('button', {name: 'Choose image or video', exact: true});
    assert.equal(await desktop(mainCard).getAttribute('aria-pressed'), 'true');
    assert.equal(await desktop(popupCard).getAttribute('aria-pressed'), 'true');
    await solid(mainCard).click();
    assert.equal(await solid(mainCard).getAttribute('aria-pressed'), 'true');
    assert.equal(await desktop(popupCard).getAttribute('aria-pressed'), 'true');
    const mainColor = mainCard.locator('input[type=color]');
    const popupColor = popupCard.locator('input[type=color]');
    const automatic = await mainColor.inputValue();
    assert.match(automatic, /^#[0-9a-f]{6}$/i);
    await mainColor.fill('#f07850');
    await main.waitForFunction(() => getComputedStyle(document.querySelector('.cg-mode-solid .cg-solid')).backgroundColor === 'rgb(240, 120, 80)');
    await solid(popupCard).click();
    assert.equal(await popupColor.inputValue(), automatic);
    await popupColor.fill('#266acc');
    await settings.waitForFunction(() => getComputedStyle(document.querySelector('.cg-mode-solid .cg-solid')).backgroundColor === 'rgb(38, 106, 204)');
    assert.equal(await mainColor.inputValue(), '#f07850');
    await popupCard.getByRole('button', {name: 'Use material color'}).click();
    assert.equal(await popupColor.inputValue(), automatic);
    assert.equal(await mainColor.inputValue(), '#f07850');

    await media(mainCard).click();
    await choose(mainCard).click();
    await main.waitForFunction(() => document.querySelector('.cg-mode-wallpaper .cg-wallpaper > div')?.style.backgroundImage.includes('main.png'));
    assert.equal(await solid(popupCard).getAttribute('aria-pressed'), 'true');
    await media(popupCard).click();
    await choose(popupCard).click();
    await settings.waitForFunction(() => document.querySelector('.cg-mode-wallpaper .cg-wallpaper > video')?.src.endsWith('popups.mp4'));
    assert.ok(await settings.getByRole('slider', {name: /Wallpaper blur/}).isVisible());
    assert.ok(await settings.getByRole('slider', {name: /Wallpaper darkness/}).isVisible());
    await settings.reload();
    await settings.getByRole('button', {name: 'Backgrounds', exact: true}).click();
    assert.equal(await media(mainCard).getAttribute('aria-pressed'), 'true');
    assert.equal(await media(popupCard).getAttribute('aria-pressed'), 'true');
    await solid(mainCard).click();
    assert.equal(await mainColor.inputValue(), '#f07850');
  } finally {
    await browser.close();
    await server.close();
  }
});
