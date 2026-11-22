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
   const context = document.createElement('canvas').getContext('2d', {willReadFrequently: true});
   const luminance = color => {
    context.clearRect(0, 0, 1, 1);
    context.fillStyle = color;
    context.fillRect(0, 0, 1, 1);
    const channels = Array.from(context.getImageData(0, 0, 1, 1).data.slice(0, 3), value => {
     const channel = value / 255;
     return channel <= .04045 ? channel / 12.92 : ((channel + .055) / 1.055) ** 2.4;
    });
    return channels[0] * .2126 + channels[1] * .7152 + channels[2] * .0722;
   };
   const contrast = (a, b) => (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
   const styles = ids.flatMap(id => ['cg-dark', 'cg-light'].map(mode => {
    windowRoot.className = ['cg-window', 'cg-material-' + id, mode].join(' ');
    const actions = [...windowRoot.querySelectorAll('.cg-toolbar > button[data-action]')];
    const primary = windowRoot.querySelector('[data-action=add]');
    const settings = windowRoot.querySelector('[data-action=settings]');
    const disabled = actions.filter(action => action.disabled);
    const disabledOpacity = Number(getComputedStyle(disabled[0]).opacity);
    const reference = luminance(mode === 'cg-light' ? '#deeff5' : '#1f283c');
    disabled.forEach(action => {action.disabled = false});
    const actionColors = actions.map(action => getComputedStyle(action.querySelector('svg')).color);
    disabled.forEach(action => {action.disabled = true});
    const style = getComputedStyle(primary);
    return {
     id,
     mode,
     alpha: Number(style.backgroundColor.match(/^rgba[(].*?, ([0-9.]+)[)]$/)?.[1]),
     background: style.backgroundImage,
     shape: style.borderRadius,
     clip: style.clipPath,
     addColor: getComputedStyle(primary.querySelector('svg')).color,
     settingsColor: getComputedStyle(settings.querySelector('svg')).color,
     actionColors,
     minIconContrast: Math.min(...actionColors.map(color => contrast(luminance(color), reference))),
     disabledOpacity,
    };
   }));
   windowRoot.className = originalClass;
   return styles;
  });
  for (const result of results) {
   assert.ok(result.alpha >= 0 && result.alpha <= 0.4, JSON.stringify(result));
   assert.equal(result.clip, 'none', 'keep the full focus and hit area');
   assert.equal(new Set(result.actionColors).size, result.actionColors.length, JSON.stringify(result));
   assert.ok(result.minIconContrast >= 3, JSON.stringify(result));
   assert.ok(result.disabledOpacity < 0.6, JSON.stringify(result));
  }
  for (const mode of ['cg-dark', 'cg-light']) {
   const variants = results.filter(result => result.mode === mode);
   assert.equal(new Set(variants.map(result => result.background)).size, variants.length);
   assert.equal(new Set(variants.map(result => result.shape)).size, variants.length);
   assert.equal(new Set(variants.map(result => result.addColor)).size, variants.length);
   assert.equal(new Set(variants.map(result => result.settingsColor)).size, variants.length);
  }

  const settings = page.locator('[data-action=settings]');
  const readLighting = element => {
   const style = getComputedStyle(element);
   return [style.backgroundImage, style.borderColor, style.boxShadow];
  };
  const idle = await settings.evaluate(readLighting);
  await settings.hover();
  const highlighted = await settings.evaluate(readLighting);
  highlighted.forEach((value, i) => assert.notEqual(value, idle[i]));
  await page.mouse.down();
  const pressed = await settings.evaluate(readLighting);
  assert.notEqual(pressed[2], highlighted[2], 'pressed reflection is inset');
  await page.mouse.move(0, 0);
  await page.mouse.up();
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
