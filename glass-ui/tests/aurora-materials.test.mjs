import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
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
test('Aurora shows translucent panes and faceted action colors with desktop acrylic', {
 skip: !executablePath || !existsSync(executablePath)
}, async () => {
 const server = await createServer({
  configFile: false,
  root: fileURLToPath(new URL('..', import.meta.url)),
  server: {host: '127.0.0.1', port: 0},
  logLevel: 'silent'
 });
 await server.listen();
 const browser = await chromium.launch({headless: true, executablePath, args: ['--no-sandbox', '--enable-unsafe-swiftshader', '--use-angle=swiftshader']});
 try {
  for (const material of ['builtin-aurora-night', 'builtin-aurora-ice']) {
   const page = await browser.newPage({viewport: {width: 960, height: 690}});
   await page.addInitScript(material => {
    localStorage.setItem('auralis-browser-guide-seen', '1');
    localStorage.setItem('mh-glass-material', material);
    localStorage.setItem('mh-glass-back-main', 'desktop');
    const draw = WebGLRenderingContext.prototype.drawArrays;
    WebGLRenderingContext.prototype.drawArrays = function (...args) {
     draw.apply(this, args);
     if (!this.canvas.classList.contains('cg-aurora-optics')) return;
     const width = this.drawingBufferWidth;
     const height = this.drawingBufferHeight;
     const pixels = new Uint8Array(width * height * 4);
     this.readPixels(0, 0, width, height, this.RGBA, this.UNSIGNED_BYTE, pixels);
     const alphas = pixels.filter((_, index) => index % 4 === 3);
     window.auroraPixels = {
      clear: alphas.some(alpha => alpha < 6),
      face: alphas.some(alpha => alpha > 26 && alpha < 80),
      rim: alphas.some(alpha => alpha > 120),
      opaque: alphas.some(alpha => alpha === 255)
     };
    };
    window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {unregisterListener: () => {}};
    window.__TAURI_INTERNALS__ = {
     metadata: {currentWindow: {label: 'main'}, currentWebview: {label: 'main'}},
     transformCallback: () => 1,
     unregisterCallback: () => {},
     invoke: async (command, args) => {
      if (command === 'dashboard_snapshot') return {downloads: [], queues: [], categories: [], speed: 0};
      if (command === 'dashboard_visuals') return {downloads: []};
      if (command === 'plugin:window|set_effects') window.auroraEffects = args.value?.effects;
      return null;
     }
    };
   }, material);
   await page.goto(server.resolvedUrls.local[0]);
   const add = page.locator('.cg-toolbar button[data-action=add]');
   const settings = page.locator('.cg-toolbar button[data-action=settings]');
   await add.waitFor();
   await page.waitForFunction(() => window.auroraEffects?.includes('acrylic'));
   assert.equal(await page.locator('.cg-wallpaper').count(), 0);
   const variant = material.endsWith('night') ? 'dark' : 'light';
   await page.locator(`.cg-aurora-optics[data-rendered='${variant}']`).waitFor();
   assert.deepEqual(await page.evaluate(() => window.auroraPixels), {
    clear: true, face: true, rim: true, opaque: false
   });
   assert.equal(
    await page.locator('.cg-content').evaluate(element => getComputedStyle(element).backdropFilter),
    'none'
   );
   const optics = await page.evaluate(() => {
    const shell = getComputedStyle(document.querySelector('.cg-content'));
    const sidebar = getComputedStyle(document.querySelector('.cg-sidebar'));
    const pane = getComputedStyle(document.querySelector('.cg-list-panel'));
    return {
     shellBase: shell.backgroundColor,
     paneBase: pane.backgroundColor,
     sidebarLayers: sidebar.backgroundImage,
     panelLayers: pane.backgroundImage
    };
   });
   assert.match(optics.shellBase, /^rgba\(/);
   assert.match(optics.paneBase, /^rgba\(/);
   assert.notEqual(optics.sidebarLayers, optics.panelLayers);
   assert.match(optics.panelLayers, material.endsWith('night') ? /radial-gradient/ : /linear-gradient/);
   const buttonSurface = element => {
    const rim = getComputedStyle(element, '::before');
    const face = getComputedStyle(element, '::after');
    return {shape: rim.clipPath, face: face.backgroundImage, ink: getComputedStyle(element.querySelector('svg')).color};
   };
   const addSurface = await add.evaluate(buttonSurface);
   const settingsSurface = await settings.evaluate(buttonSurface);
   assert.match(addSurface.shape, /^polygon\(/);
   assert.notEqual(addSurface.ink, settingsSurface.ink);
   if (material.endsWith('night')) {
    assert.equal(addSurface.ink, 'rgb(8, 233, 121)');
    assert.equal(settingsSurface.ink, 'rgb(184, 64, 255)');
   } else {
    assert.match(addSurface.ink, /^color\(srgb /);
    assert.match(settingsSurface.ink, /^color\(srgb /);
   }
   await settings.hover();
   assert.notEqual((await settings.evaluate(buttonSurface)).face, settingsSurface.face);
   await page.close();
  }
 } finally {
  await browser.close();
  await server.close();
 }
});
