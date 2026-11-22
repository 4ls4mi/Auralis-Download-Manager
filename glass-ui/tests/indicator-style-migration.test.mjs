import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executablePath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('legacy removed indicator choices migrate to supported styles', {skip:!executablePath||!existsSync(executablePath)}, async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath,args:['--no-sandbox']});
 try {const page=await browser.newPage();await page.goto(server.resolvedUrls.local[0]);const a=await page.evaluate(async()=>{localStorage.clear();localStorage.setItem('mh-glass-progress-material','liquid-aero');localStorage.setItem('mh-glass-connection-material','liquid-crystal');localStorage.setItem('mh-glass-graph-material','frosted-ribbon');localStorage.setItem('mh-glass-progress-shape','droplet');localStorage.setItem('mh-glass-indicator','neon');const m=await import('/src/CrystalShared.tsx');return m.loadAppearance()});assert.equal(a.progressMaterial,'liquid-glass');assert.equal(a.connectionMaterial,'liquid-glass');assert.equal(a.graphMaterial,'liquid-glass');assert.equal(a.progressShape,'bubble');assert.equal(a.indicator,'blue-purple');} finally {await browser.close();await server.close()}
});
