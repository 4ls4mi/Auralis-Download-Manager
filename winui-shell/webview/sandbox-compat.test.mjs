import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
const source=readFileSync(new URL('./sandbox-compat.js',import.meta.url),'utf8');
test('sandbox restricts downloader requests and allows isolated display preferences',async()=>{
 let listener;const messages=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>messages.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('dashboard_snapshot');assert.equal(messages[0].command,'dashboard_snapshot');listener({data:{id:messages[0].id,ok:true,value:{downloads:[]}}});assert.equal((await pending).downloads.length,0);
 const setting=context.__TAURI_INTERNALS__.invoke('update_glass_setting',{key:'show_complete',value:'false'});assert.equal(messages[1].key,'show_complete');listener({data:{id:messages[1].id,ok:true,value:{saved:true}}});assert.equal((await setting).saved,true);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('update_glass_setting',{key:'advanced_integration',value:'true'}),/unavailable/);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('download_action',{action:'start',ids:[1]}),/unavailable/);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('add_download',{url:'https://example.com'}),/unavailable/);
 assert.throws(()=>new context.WebSocket('wss://example.com'),/disabled/);
});
