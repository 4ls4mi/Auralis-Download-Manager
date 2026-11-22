import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
test('packaged browser helper uses the Auralis name and keeps legacy lookup compatibility',()=>{
 const config=JSON.parse(readFileSync(new URL('../src-tauri/tauri.conf.json',import.meta.url),'utf8'));
 assert.equal(config.bundle.resources['resources/misterdownloadmanager-nmhost.exe'],'auralis-browser-host.exe');
 const source=readFileSync(new URL('../src-tauri/src/main.rs',import.meta.url),'utf8');
 const start=source.indexOf('fn native_host_candidates('), end=source.indexOf('fn register_browser_host(',start);
 assert.ok(start>=0&&end>start);
 const candidates=source.slice(start,end);
 assert.ok(candidates.indexOf('auralis-browser-host.exe')>=0);
 assert.ok(candidates.indexOf('misterdownloadmanager-nmhost.exe')>candidates.indexOf('auralis-browser-host.exe'));
});
