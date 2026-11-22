import test from 'node:test';import assert from 'node:assert/strict';import {existsSync} from 'node:fs';import {fileURLToPath} from 'node:url';import {chromium} from 'playwright-core';import {createServer} from 'vite';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('preferences backup exports selected UI options and restores allowed values',{skip:!executablePath||!existsSync(executablePath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try{const page=await browser.newPage();await page.addInitScript(()=>{if(!sessionStorage.getItem('initialized')){localStorage.setItem('mh-glass-indicator','blue-purple');localStorage.setItem('auralis-update-presentation','dialog');sessionStorage.setItem('initialized','1')}window.calls=[];window.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener:()=>{}};window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'settings'},currentWebview:{label:'settings'}},transformCallback:()=>1,unregisterCallback:()=>{},invoke:async(cmd,args)=>{window.calls.push({cmd,args});if(cmd==='startup_settings')return {enabled:false,mode:'minimized'};if(cmd==='glass_settings')return {category_dirs:[]};if(cmd==='dashboard_snapshot')return {queues:[]};if(cmd==='export_preferences')return 'backup.json';if(cmd==='import_preferences')return {'mh-glass-indicator':'aurora','auralis-update-presentation':'toast','mh-glass-large-theme-collection':'x'.repeat(20000),'unrelated-key':'must-not-import'};return null}}});
 await page.goto(server.resolvedUrls.local[0]+'?settings=1');await page.getByRole('button',{name:'Save backup…'}).click();const exported=await page.evaluate(()=>window.calls.find(c=>c.cmd==='export_preferences')?.args.ui);assert.equal(exported['mh-glass-indicator'],'blue-purple');assert.equal(exported['auralis-update-presentation'],'dialog');assert.equal(exported['unrelated-key'],undefined);
 await page.getByRole('button',{name:'Restore backup…'}).click();await page.waitForFunction(()=>localStorage.getItem('mh-glass-indicator')==='aurora');assert.equal(await page.evaluate(()=>localStorage.getItem('unrelated-key')),null);assert.equal(await page.evaluate(()=>localStorage.getItem('mh-glass-large-theme-collection')?.length),20000);
 }finally{await browser.close();await server.close()}
});

test('download backups preserve supported preferences and refresh restored settings', {
  skip: !executablePath || !existsSync(executablePath),
}, async () => {
  const server = await createServer({
    configFile: false,
    root: fileURLToPath(new URL('..', import.meta.url)),
    server: {host: '127.0.0.1', port: 0},
    logLevel: 'silent',
  });
  await server.listen();
  const browser = await chromium.launch({headless: true, executablePath, args: ['--no-sandbox']});
  try {
    const page = await browser.newPage();
    await page.addInitScript(() => {
      localStorage.setItem('mh-glass-material', 'rose-pine');
      localStorage.setItem('mh-glass-glass-translucency', '37');
      localStorage.setItem('unrelated-key', 'keep');
      window.calls = [];
      window.archiveRestore = null;
      window.restoredStartup = false;
      window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {unregisterListener: () => {}};
      window.__TAURI_INTERNALS__ = {
        metadata: {currentWindow: {label: 'settings'}, currentWebview: {label: 'settings'}},
        transformCallback: () => 1,
        unregisterCallback: () => {},
        invoke: async (cmd, args) => {
          window.calls.push({cmd, args});
          if (cmd === 'startup_settings') return {enabled: window.restoredStartup, mode: 'window'};
          if (cmd === 'glass_settings') return {category_dirs: []};
          if (cmd === 'dashboard_snapshot') return {queues: []};
          if (cmd === 'export_full_backup') return new Promise(resolve => {window.finishArchiveExport = resolve});
          if (cmd === 'import_full_backup') {
            window.restoredStartup = Boolean(window.archiveRestore);
            return window.archiveRestore;
          }
          return null;
        },
      };
    });

    await page.goto(server.resolvedUrls.local[0] + '?settings=1');
    const save = page.getByRole('button', {name: 'Back up downloads…'});
    const restore = page.getByRole('button', {name: 'Restore downloads…'});
    await save.click();
    await page.getByRole('status').filter({hasText: 'Creating download backup…'}).waitFor();
    assert.equal(await restore.isDisabled(), true);
    const saved = await page.evaluate(() => window.calls.find(call => call.cmd === 'export_full_backup').args.ui);
    assert.equal(saved['mh-glass-material'], 'rose-pine');
    assert.equal(saved['mh-glass-glass-translucency'], '37');
    assert.equal(saved['unrelated-key'], undefined);

    await page.evaluate(() => window.finishArchiveExport({path: 'example.auralis-backup'}));
    await page.getByText('Download backup saved to example.auralis-backup.').waitFor();
    await restore.click();
    await page.waitForFunction(() => window.calls.some(call => call.cmd === 'import_full_backup'));
    assert.equal(await page.getByText(/Download backup restored/).count(), 0);
    assert.equal(await page.evaluate(() => localStorage.getItem('mh-glass-material')), 'rose-pine');

    await page.evaluate(() => {
      window.archiveRestore = {
        path: 'example.auralis-backup',
        restored_to: 'Restored Auralis Downloads',
        ui_complete: true,
        warning: 'Could not update the Windows startup entry.',
        ui: {
          'mh-glass-material': 'builtin-aurora-night',
          'unrelated-key': 'ignore',
        },
      };
    });
    await restore.click();
    await page.getByText('Download backup restored to Restored Auralis Downloads.').waitFor();
    await page.getByText('Could not update the Windows startup entry.').waitFor();
    await page.locator('.cg-material-builtin-aurora-night').waitFor();
    await page.waitForFunction(() => document.querySelector('input[type=checkbox]').checked);
    const preferences = await page.evaluate(() => ({
      material: localStorage.getItem('mh-glass-material'),
      translucency: localStorage.getItem('mh-glass-glass-translucency'),
      unrelated: localStorage.getItem('unrelated-key'),
    }));
    assert.deepEqual(preferences, {material: 'builtin-aurora-night', translucency: null, unrelated: 'keep'});
    assert.equal(await page.getByRole('checkbox', {name: /Start Auralis with Windows/}).isChecked(), true);
  } finally {
    await browser.close();
    await server.close();
  }
});
