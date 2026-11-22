import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';

const executablePath = process.env.AURALIS_TEST_BROWSER ||
  (process.platform === 'linux' ? '/usr/bin/chromium' : '');

test('every material gives translucent actions distinct shapes, colors, and legible states', {
 skip: !executablePath || !existsSync(executablePath)
}, async () => {
 const server = await createServer({
  configFile: false,
  root: fileURLToPath(new URL('..', import.meta.url)),
  server: {host: '127.0.0.1', port: 0},
  logLevel: 'silent'
 });
 await server.listen();
 const browser = await chromium.launch({headless: true, executablePath, args: ['--no-sandbox']});
 try {
  const page = await browser.newPage({viewport: {width: 1100, height: 720}, reducedMotion: 'reduce'});
  await page.addInitScript(() => {
   localStorage.setItem('auralis-browser-guide-seen', '1');
   window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {unregisterListener: () => {}};
   window.__TAURI_INTERNALS__ = {
    metadata: {currentWindow: {label: 'main'}, currentWebview: {label: 'main'}},
    transformCallback: () => 1,
    unregisterCallback: () => {},
    invoke: async command => {
     if (command === 'dashboard_snapshot') return {downloads: [], queues: [], categories: [], speed: 0};
     if (command === 'dashboard_visuals') return {downloads: []};
     return null;
    }
   };
  });
  await page.goto(server.resolvedUrls.local[0]);
  await page.waitForSelector('.cg-toolbar');
  const results = await page.evaluate(() => {
   const windowRoot = document.querySelector('.cg-window');
   const ids = [
    'brushed-glass', 'frosted-water-351', 'rose-pine', 'oversimplified',
    'builtin-obsidian-matte', 'builtin-smoked-glass', 'builtin-black-glass',
    'builtin-pearl-frost', 'builtin-aurora-night', 'builtin-aurora-ice'
   ];
   const originalClass = windowRoot.className;
   const styles = ids.map(id => {
    windowRoot.className = `cg-window cg-material-${id} ${id === 'builtin-aurora-ice' ? 'cg-light' : 'cg-dark'}`;
    const primary = windowRoot.querySelector('[data-action=add]');
    const settings = windowRoot.querySelector('[data-action=settings]');
    const disabled = getComputedStyle(windowRoot.querySelector('[data-action=start]'));
    const style = getComputedStyle(primary);
    return {
     id,
     alpha: Number(style.backgroundColor.match(/^rgba\(.*?, ([\d.]+)\)$/)?.[1]),
     background: style.backgroundImage,
     shape: style.borderRadius,
     clip: style.clipPath,
     addColor: getComputedStyle(primary.querySelector('svg')).color,
     settingsColor: getComputedStyle(settings.querySelector('svg')).color,
     disabledOpacity: Number(disabled.opacity),
    };
   });
   windowRoot.className = originalClass;
   return styles;
  });
  for (const result of results) {
   assert.ok(result.alpha >= 0 && result.alpha <= 0.4, JSON.stringify(result));
   assert.equal(result.clip, 'none', 'keep the full focus and hit area');
   assert.notEqual(result.addColor, result.settingsColor);
   assert.ok(result.disabledOpacity < 0.6, JSON.stringify(result));
  }
  assert.equal(new Set(results.map(result => result.background)).size, results.length);
  assert.equal(new Set(results.map(result => result.shape)).size, results.length);
  assert.equal(new Set(results.map(result => result.addColor)).size, results.length);
  assert.equal(new Set(results.map(result => result.settingsColor)).size, results.length);

  const settings = page.locator('[data-action=settings]');
  const idle = await settings.evaluate(element => getComputedStyle(element).backgroundImage);
  await settings.hover();
  assert.notEqual(await settings.evaluate(element => getComputedStyle(element).backgroundImage), idle);
  await page.locator('[data-action=add]').focus();
  await page.keyboard.press('Tab');
  const focused = page.locator('.cg-toolbar > button:focus-visible');
  assert.ok(await focused.count(), 'toolbar can receive focus by keyboard');
  assert.equal(await focused.evaluate(element => getComputedStyle(element).outlineStyle), 'solid');
 } finally {
  await browser.close();
  await server.close();
 }
});
