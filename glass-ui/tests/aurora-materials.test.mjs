import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');

function cssAlpha(color) {
 return color.startsWith('rgba(') ? Number(color.slice(5, -1).split(',').at(-1)) : 1;
}
test('dark and light Aurora materials stay distinct and save across reload', {skip:!executablePath||!existsSync(executablePath)}, async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try {const page=await browser.newPage();await page.addInitScript(()=>{window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async cmd=>cmd==='glass_settings'?{}:null}});
 await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Appearance');
 const styles=[];
 for(const [label,id,kind] of [['Aurora Glass — Dark','builtin-aurora-night','cg-dark'],['Aurora Glass — Light','builtin-aurora-ice','cg-light']]){
  const option=page.getByRole('button',{name:label,exact:false});await option.click();await page.waitForSelector('.cg-material-'+id+'.'+kind,{state:'attached'});
  assert.equal(await page.evaluate(()=>localStorage.getItem('mh-glass-material')),id);
  styles.push(await page.locator('.cg-content').evaluate(el=>getComputedStyle(el).backgroundImage));
  const titleColor=await page.locator('.cg-title').evaluate(el=>getComputedStyle(el).color);const rgb=titleColor.match(/\d+/g).map(Number);assert.ok(kind==='cg-light'?rgb[0]<100:rgb[0]>180,`${label}: ${titleColor}`);
  await page.reload();await page.waitForSelector('.cg-material-'+id+'.'+kind,{state:'attached'});
 }
 assert.notEqual(styles[0],styles[1]);
 } finally {await browser.close();await server.close()}
});
test('Aurora shows translucent panes and action colors with desktop acrylic', {
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
  for (const material of ['builtin-aurora-night', 'builtin-aurora-ice']) {
   const context = await browser.newContext({viewport: {width: 960, height: 690}});
   await context.addInitScript(material => {
    localStorage.setItem('auralis-browser-guide-seen', '1');
    localStorage.setItem('mh-glass-material', material);
    localStorage.setItem('mh-glass-back-main', 'desktop');
    localStorage.setItem('mh-glass-back-details', 'desktop');
    const label = new URLSearchParams(location.search).has('settings') ? 'settings' : 'main';
    window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {unregisterListener: () => {}};
    window.__TAURI_INTERNALS__ = {
     metadata: {currentWindow: {label}, currentWebview: {label}},
     transformCallback: () => 1,
     unregisterCallback: () => {},
     invoke: async (command, args) => {
      if (command === 'dashboard_snapshot') return {downloads: [], queues: [], categories: [], speed: 0};
      if (command === 'dashboard_visuals') return {downloads: []};
      if (command === 'set_material_acrylic') { window.auroraAcrylic = args; return true; }
      return null;
     }
    };
   }, material);
   const page = await context.newPage();
   await page.goto(server.resolvedUrls.local[0]);
   const add = page.locator('.cg-toolbar button[data-action=add]');
   const settings = page.locator('.cg-toolbar button[data-action=settings]');
   await add.waitFor();
   await page.waitForFunction(() => window.auroraAcrylic?.enabled);
   assert.equal(await page.locator('.cg-wallpaper').count(), 0);
   assert.equal(await page.locator('.cg-aurora-optics').count(), 0);
   assert.equal(
    await page.locator('.cg-content').evaluate(element => getComputedStyle(element).backdropFilter),
    'none'
   );
   const optics = await page.evaluate(() => {
    const shell = getComputedStyle(document.querySelector('.cg-content'));
    const sidebar = getComputedStyle(document.querySelector('.cg-sidebar'));
    const pane = getComputedStyle(document.querySelector('.cg-list-panel'));
    const title = getComputedStyle(document.querySelector('.cg-window-top'));
    const toolbar = getComputedStyle(document.querySelector('.cg-toolbar'));
    return {
     shellBase: shell.backgroundColor,
     paneBase: pane.backgroundColor,
     titleBase: title.backgroundColor,
     toolbarBase: toolbar.backgroundColor,
     sidebarLayers: sidebar.backgroundImage,
     paneRim: pane.boxShadow,
     panelLayers: pane.backgroundImage
    };
   });
   const expectedAlpha = material.endsWith('night') ? .28 : .22;
   assert.ok(Math.abs(cssAlpha(optics.shellBase) - expectedAlpha) < .01);
   assert.equal(await page.evaluate(() => window.auroraAcrylic.dark), material.endsWith('night'));
   assert.ok(cssAlpha(optics.paneBase) > 0 && cssAlpha(optics.paneBase) < cssAlpha(optics.titleBase));
   assert.ok(cssAlpha(optics.paneBase) < cssAlpha(optics.toolbarBase));
   assert.ok(cssAlpha(optics.titleBase) < cssAlpha(optics.shellBase));
   assert.ok(cssAlpha(optics.toolbarBase) < cssAlpha(optics.shellBase));
   assert.notEqual(optics.sidebarLayers, optics.panelLayers);
   assert.match(optics.panelLayers, material.endsWith('night') ? /radial-gradient/ : /linear-gradient/);
   assert.match(optics.paneRim, /inset/);
   const buttonSurface = element => {
    const style = getComputedStyle(element);
    return {
     radius: style.borderRadius,
     clip: style.clipPath,
     rim: getComputedStyle(element, '::before').content,
     face: style.backgroundColor,
     layers: style.backgroundImage,
     ink: getComputedStyle(element.querySelector('svg')).color
    };
   };
   const addSurface = await add.evaluate(buttonSurface);
   const settingsSurface = await settings.evaluate(buttonSurface);
   assert.equal(addSurface.radius, material.endsWith('night') ? '5px 15px' : '34% 34% 25% 25% / 28% 28% 24% 24%');
   assert.equal(addSurface.clip, 'none');
   assert.equal(addSurface.rim, 'none');
   assert.match(addSurface.face, /^rgba\(/);
   assert.notEqual(addSurface.ink, settingsSurface.ink);
   await settings.hover();
   assert.notEqual((await settings.evaluate(buttonSurface)).layers, settingsSurface.layers);

   const settingsPage = await context.newPage();
   await settingsPage.goto(server.resolvedUrls.local[0] + '?settings=1&tab=Appearance');
   await settingsPage.waitForFunction(() => window.auroraAcrylic?.enabled);
   assert.equal(await settingsPage.locator('.cg-wallpaper').count(), 0);
   assert.equal(await settingsPage.locator('.cg-aurora-optics').count(), 0);
   const settingsShell = settingsPage.locator('.cg-content');
   assert.equal(await settingsShell.evaluate(element => getComputedStyle(element).backgroundColor), optics.shellBase);
   assert.equal(await settingsPage.locator('.cg-window-top').evaluate(element => getComputedStyle(element).backgroundColor), optics.titleBase);
   const slider = settingsPage.getByRole('slider', {name: 'Glass translucency', exact: false});
   await slider.press('End');
   await page.waitForFunction(() => document.querySelector('.cg-window').style.getPropertyValue('--glass-window-opacity') === '0');
   for (const frame of [page, settingsPage]) {
    const surfaces = await frame.evaluate(() => ({
     shell: getComputedStyle(document.querySelector('.cg-content')).backgroundColor,
     pane: getComputedStyle(document.querySelector('.cg-sidebar,.cg-settings-nav')).backgroundColor
    }));
    assert.equal(cssAlpha(surfaces.shell), 0);
    assert.equal(cssAlpha(surfaces.pane), 0);
   }
   await context.close();
  }
 } finally {
  await browser.close();
  await server.close();
 }
});
