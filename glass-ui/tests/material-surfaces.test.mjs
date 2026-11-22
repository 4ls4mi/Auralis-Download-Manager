import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';
import { createServer } from 'vite';

const executablePath = process.env.AURALIS_TEST_BROWSER || (process.platform === 'linux' ? '/usr/bin/chromium' : '');
const labels = [
  'Brushed Glass', 'Frosted Layers', 'Rose Pine', 'Oversimplified & Accentuated',
  'Aurora Glass — Dark', 'Aurora Glass — Light', 'Matte Obsidian', 'Smoked Glass',
  'Black Blur Glass', 'Pearl Frost'
];

function rgba(value) {
  const components = value.match(/^rgba\((\d+), (\d+), (\d+), ([\d.]+)\)$/);
  assert.ok(components, `Expected a translucent RGB color, got ${value}`);
  return { color: components.slice(1, 4).join(','), alpha: Number(components[4]) };
}

test('all built-in materials have distinct translucent palettes and layouts at the default window size', {
  skip: !executablePath || !existsSync(executablePath)
}, async () => {
  const server = await createServer({
    configFile: false,
    root: fileURLToPath(new URL('..', import.meta.url)),
    server: { host: '127.0.0.1', port: 0 },
    logLevel: 'silent'
  });
  await server.listen();
  const browser = await chromium.launch({ headless: true, executablePath, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ viewport: { width: 814, height: 468 } });
    await context.addInitScript(() => {
      localStorage.setItem('auralis-browser-guide-seen', '1');
      localStorage.setItem('mh-glass-back-main', 'desktop');
      localStorage.setItem('mh-glass-back-details', 'desktop');
      const label = new URLSearchParams(location.search).has('settings') ? 'settings' : 'main';
      window.__TAURI_EVENT_PLUGIN_INTERNALS__ = { unregisterListener: () => {} };
      window.__TAURI_INTERNALS__ = {
        metadata: { currentWindow: { label }, currentWebview: { label } },
        transformCallback: () => 1,
        unregisterCallback: () => {},
        invoke: async command => {
          if (command === 'dashboard_snapshot') return { downloads: [], queues: [], categories: [], speed: 0 };
          if (command === 'dashboard_visuals') return { downloads: [] };
          if (command === 'set_material_acrylic') return true;
          return null;
        }
      };
    });
    const main = await context.newPage();
    const settings = await context.newPage();
    const origin = server.resolvedUrls.local[0];
    await main.goto(origin);
    await settings.goto(origin + '?settings=1&tab=Appearance');
    const palettes = new Set();
    const layouts = new Set();
    const materialIds = [];
    for (const label of labels) {
      const option = settings.getByRole('button', { name: label, exact: false });
      await option.click({ timeout: 7000 });
      const id = await settings.evaluate(() => localStorage.getItem('mh-glass-material'));
      await main.locator(`.cg-material-${id}`).waitFor({ state: 'attached', timeout: 7000 });
      materialIds.push(id);
      const styles = await main.evaluate(() => {
        const shell = getComputedStyle(document.querySelector('.cg-content'));
        const list = getComputedStyle(document.querySelector('.cg-list-panel'));
        const nav = getComputedStyle(document.querySelector('.cg-sidebar'));
        const heading = getComputedStyle(document.querySelector('.cg-list-title'));
        const workspace = getComputedStyle(document.querySelector('.cg-workspace'));
        const mainBody = getComputedStyle(document.querySelector('.cg-main-body'));
        const overflow = [...document.querySelectorAll('.cg-content,.cg-workspace,.cg-toolbar')].filter(el => el.scrollWidth > el.clientWidth + 1).map(el => el.className);
        return {
          shell: shell.backgroundColor,
          pane: list.backgroundColor,
          radius: list.borderRadius,
          shade: list.boxShadow,
          navDirection: nav.flexDirection,
          overflow,
          heading: heading.display,
          mainBody: mainBody.display,
          grid: workspace.gridTemplateColumns,
          gap: workspace.columnGap
        };
      });
      const shell = rgba(styles.shell);
      const pane = rgba(styles.pane);
      assert.ok(shell.alpha > 0 && shell.alpha < .8, `${label} shell alpha: ${shell.alpha}`);
      assert.ok(pane.alpha < shell.alpha, `${label} inset pane alpha: ${pane.alpha}`);
      assert.match(styles.shade, /inset/);
      assert.deepEqual(styles.overflow, [], `${label} default-width overflow`);
      assert.equal(await settings.locator('.cg-content').evaluate(el => getComputedStyle(el).backgroundColor), styles.shell);
      if (id === 'oversimplified') assert.equal(styles.navDirection, 'row');
      if (id === 'rose-pine') assert.equal(styles.heading, 'grid');
      if (id === 'builtin-obsidian-matte') assert.equal(styles.mainBody, 'grid');
      if (id === 'builtin-smoked-glass') assert.equal(styles.gap, '0px');
      palettes.add(shell.color);
      layouts.add([styles.radius, styles.grid, styles.gap, styles.navDirection].join('|'));
    }
    assert.equal(palettes.size, labels.length);
    assert.equal(layouts.size, labels.length);

    await main.setViewportSize({ width: 560, height: 450 });
    for (const [index, label] of labels.entries()) {
      await settings.getByRole('button', { name: label, exact: false }).click({ timeout: 7000 });
      await main.locator(`.cg-material-${materialIds[index]}`).waitFor({ state: 'attached', timeout: 7000 });
      const overflow = await main.evaluate(() => [...document.querySelectorAll('.cg-content,.cg-workspace,.cg-toolbar')]
        .filter(el => el.scrollWidth > el.clientWidth + 1)
        .map(el => el.className));
      assert.deepEqual(overflow, [], `${label} compact-width overflow`);
    }
  } finally {
    await browser.close();
    await server.close();
  }
});
