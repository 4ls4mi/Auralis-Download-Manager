import test from 'node:test';import assert from 'node:assert/strict';import {existsSync} from 'node:fs';import {fileURLToPath} from 'node:url';import {chromium} from 'playwright-core';import {createServer} from 'vite';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('white theme has dark labels and each material chooses its backdrop',{skip:!executablePath||!existsSync(executablePath)},async()=>{const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});try{const page=await browser.newPage();await page.addInitScript(()=>{localStorage.setItem('mh-glass-theme','white-frost');localStorage.setItem('mh-glass-material','frosted-water-351');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{if(cmd==='glass_settings')return {};if(cmd==='glass_tool')return {tools:[],job:null};return null}}});await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Appearance');await page.getByText('Color themes',{exact:true}).waitFor();for(const selector of ['.cg-title','.cg-settings-nav button span','.cg-color-choices button']){const color=await page.locator(selector).first().evaluate(el=>getComputedStyle(el).color);const rgb=color.match(/\d+/g).map(Number);assert.ok(rgb.slice(0,3).every(v=>v<100),`${selector}: ${color}`)}assert.ok(await page.locator('.cg-window.cg-surface-frosted').count());await page.getByRole('button',{name:'Brushed Glass',exact:true}).click();assert.equal(await page.evaluate(()=>localStorage.getItem('mh-glass-material')),'brushed-glass');assert.ok(await page.locator('.cg-window.cg-surface-soft').count());assert.equal(await page.getByText('Windows backdrop blur',{exact:true}).count(),0)}finally{await browser.close();await server.close()}});
test('toolbar buttons remain compact at large widths and use varied accents',{skip:!executablePath||!existsSync(executablePath)},async()=>{const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});try{const page=await browser.newPage({viewport:{width:1800,height:900}});await page.addInitScript(()=>{localStorage.setItem('auralis-browser-guide-seen','1');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async cmd=>cmd==='dashboard_snapshot'?{downloads:[],queues:[],categories:[],speed:0}:cmd==='dashboard_visuals'?{downloads:[]}:cmd==='glass_update_check'?{state:'latest'}:null}});await page.goto(server.resolvedUrls.local[0]);await page.waitForSelector('.cg-toolbar button svg');const values=await page.locator('.cg-toolbar button').evaluateAll(els=>els.map(el=>({width:el.getBoundingClientRect().width,color:getComputedStyle(el.querySelector('svg')).color})));assert.ok(values.every(v=>v.width<=60),JSON.stringify(values));assert.ok(new Set(values.map(v=>v.color)).size>=3,JSON.stringify(values))}finally{await browser.close();await server.close()}});
test('download table and connection status are readable on light themes',{skip:!executablePath||!existsSync(executablePath)},async()=>{const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});try{const page=await browser.newPage({viewport:{width:960,height:1040}});await page.addInitScript(()=>{localStorage.setItem('auralis-browser-guide-seen','1');localStorage.setItem('mh-glass-theme','white-frost');localStorage.setItem('mh-glass-material','frosted-water-351');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async cmd=>cmd==='dashboard_snapshot'?{downloads:[{id:1,file:'example.zip',url:'https://example.com/x',path:'C:/x',status:'Complete',size:1000,downloaded:1000,speed:0,added:null,category:'General'}],queues:[],categories:[],speed:0}:cmd==='dashboard_visuals'?{downloads:[]}:cmd==='glass_update_check'?{state:'latest'}:null}});await page.goto(server.resolvedUrls.local[0]);await page.locator('.cg-row').first().waitFor();for(const selector of ['.cg-window-top .cg-muted','.cg-cols>span','.cg-row>span:nth-of-type(1)','.cg-row .cg-status','.cg-footer-version']){const el=page.locator(selector).first();const color=await el.evaluate(e=>getComputedStyle(e).color);const rgb=color.match(/\d+/g).map(Number);assert.ok(rgb.slice(0,3).every(v=>v<170),`${selector}: ${color}`)}}finally{await browser.close();await server.close()}});
test('snapped windows switch to a rectangular layout and restore their material',{skip:!executablePath||!existsSync(executablePath)},async()=>{const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});try{const page=await browser.newPage();await page.addInitScript(()=>{window.mockSnapped=true;window.shapeCalls=[];localStorage.setItem('auralis-browser-guide-seen','1');window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{if(cmd==='plugin:window|is_maximized')return false;if(cmd==='plugin:window|outer_position')return window.mockSnapped?{x:960,y:0}:{x:150,y:100};if(cmd==='plugin:window|outer_size')return window.mockSnapped?{width:960,height:1040}:{width:960,height:690};if(cmd==='plugin:window|current_monitor')return {name:'test',scaleFactor:1,position:{x:0,y:0},size:{width:1920,height:1080},workArea:{position:{x:0,y:0},size:{width:1920,height:1040}}};if(cmd==='set_material_window_shape'){window.shapeCalls.push(args);return null}if(cmd==='dashboard_snapshot')return {downloads:[],queues:[],categories:[],speed:0};if(cmd==='dashboard_visuals')return {downloads:[]};return null}}});await page.goto(server.resolvedUrls.local[0]);await page.locator('.cg-window.cg-tiled').waitFor();await page.waitForFunction(()=>window.shapeCalls.some(c=>c.flat===true));await page.evaluate(()=>{window.mockSnapped=false;window.dispatchEvent(new Event('resize'))});await page.waitForFunction(()=>!document.querySelector('.cg-window.cg-tiled'));await page.waitForFunction(()=>window.shapeCalls.at(-1)?.flat===false)}finally{await browser.close();await server.close()}});

test('navigation, tabs and caption controls carry the material palette through hover and focus', {
  skip: !executablePath || !existsSync(executablePath),
}, async () => {
  const server = await createServer({
    configFile: false,
    root: fileURLToPath(new URL('..', import.meta.url)),
    server: { host: '127.0.0.1', port: 0 },
    logLevel: 'silent',
  });
  await server.listen();
  const browser = await chromium.launch({headless: true, executablePath, args: ['--no-sandbox']});
  try {
    const page = await browser.newPage({viewport: {width: 1024, height: 720}});
    await page.addInitScript(() => {
      window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {unregisterListener: () => {}};
      window.__TAURI_INTERNALS__ = {
        metadata: {currentWindow: {label: 'settings'}, currentWebview: {label: 'settings'}},
        transformCallback: () => 1,
        unregisterCallback: () => {},
        invoke: async cmd => cmd === 'glass_settings' ? {} : null,
      };
    });
    const identities = new Set();
    for (const material of ['builtin-aurora-ice', 'builtin-smoked-glass']) {
      await page.goto(server.resolvedUrls.local[0] + '?settings=1&tab=Appearance');
      await page.evaluate(material => localStorage.setItem('mh-glass-material', material), material);
      await page.reload();
      await page.locator(`.cg-window.cg-material-${material}`).waitFor();
      const windowButtons = await page.locator('.cg-winbuttons button svg').evaluateAll(
        icons => icons.map(icon => getComputedStyle(icon).color)
      );
      assert.equal(new Set(windowButtons).size, 4);
      identities.add(windowButtons.join(','));
      const tabs = await page.locator('.cg-appearance-tabs button').evaluateAll(
        buttons => buttons.map(button => getComputedStyle(button).backgroundImage)
      );
      assert.equal(new Set(tabs).size, tabs.length);

      const general = page.getByRole('button', {name: 'General', exact: true});
      const idle = await general.evaluate(button => getComputedStyle(button).backgroundImage);
      await general.hover();
      await page.waitForFunction(idle => {
        const button = document.querySelector('.cg-settings-nav button');
        return getComputedStyle(button).backgroundImage !== idle;
      }, idle);
      // Starting at the menu rail also checks that a keyboard-only action shows an outline.
      await page.keyboard.press('Tab');
      const focused = page.locator('button:focus-visible');
      await focused.waitFor();
      assert.equal(await focused.evaluate(button => getComputedStyle(button).outlineStyle), 'solid');
    }
    assert.equal(identities.size, 2);
  } finally {
    await browser.close();
    await server.close();
  }
});
