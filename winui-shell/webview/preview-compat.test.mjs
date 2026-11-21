import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
const source=readFileSync(new URL('./preview-compat.js',import.meta.url),'utf8');
test('visual preview is isolated and forwards only appearance to the host',async()=>{
 let listener;const messages=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>messages.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 assert.equal((await context.__TAURI_INTERNALS__.invoke('dashboard_snapshot')).downloads.length,0);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('download_action',{action:'start',ids:[1]}),/unavailable/);
 assert.throws(()=>new context.WebSocket('wss://example.com'),/disabled/);
 const pending=context.__AURALIS_WINUI__.setAppearance({material:'window-glass',tint:[1,2,3],light:false});
 assert.equal(messages[0].command,'set_native_appearance');listener({data:{id:messages[0].id,ok:true,value:{applied:true}}});assert.equal((await pending).applied,true);
});

test('native backdrop preview installs translucent desktop layers for every material',()=>{
 let ready; let added;
 const document={documentElement:{dataset:{}},addEventListener:(_name,fn)=>{ready=fn},createElement:()=>({}),head:{append:node=>{added=node}}};
 const context={document,chrome:{webview:{addEventListener(){},postMessage(){}}},setTimeout,clearTimeout};
 runInNewContext(source,context);
 ready();
 assert.equal(document.documentElement.dataset.auralisWinuiPreview,'true');
 assert.match(added.textContent,/\.cg-window\.cg-mode-desktop \.cg-content/);
 assert.match(added.textContent,/\.cg-frost-canvas/);
 assert.doesNotMatch(added.textContent,/:not\(\.cg-material-frosted-water-351\)/);
});
