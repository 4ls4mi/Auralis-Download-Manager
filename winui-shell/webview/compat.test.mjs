import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
const source=readFileSync(new URL('./compat.js',import.meta.url),'utf8');
function setup(){let listener;const sent=[];const webview={addEventListener:(name,fn)=>{assert.equal(name,'message');listener=fn},postMessage:value=>sent.push(value)};const context={chrome:{webview},setTimeout,clearTimeout};runInNewContext(source,context);return {context,sent,reply:data=>listener({data})}}
test('forwards only the approved snapshot and one-download actions',async()=>{const {context,sent,reply}=setup();const invoke=context.__TAURI_INTERNALS__.invoke;const pending=invoke('download_action',{action:'pause',ids:[7]});assert.equal(sent[0].command,'pause_download');assert.equal(sent[0].downloadId,7);reply({id:sent[0].id,ok:true,value:{done:[7]}});assert.deepEqual((await pending).done,[7]);await assert.rejects(invoke('download_action',{action:'delete',ids:[7]}),/not implemented/);await assert.rejects(invoke('dashboard_snapshot_unsafe'),/not implemented/);});
test('uses returned errors and ignores unknown response ids',async()=>{const {context,sent,reply}=setup();const pending=context.__TAURI_INTERNALS__.invoke('dashboard_snapshot');reply({id:999,ok:true,value:{}});reply({id:sent[0].id,ok:false,error:'Unavailable'});await assert.rejects(pending,/Unavailable/)});
test('forwards settings changes as a named, string-valued request',async()=>{const {context,sent,reply}=setup();const invoke=context.__TAURI_INTERNALS__.invoke;const pending=invoke('update_glass_setting',{key:'show_complete',value:'false'});assert.equal(sent[0].command,'update_glass_setting');assert.equal(sent[0].key,'show_complete');assert.equal(sent[0].value,'false');reply({id:sent[0].id,ok:true,value:{saved:true}});assert.equal((await pending).saved,true);await assert.rejects(invoke('update_glass_setting',{key:'show_complete',value:false}),/not implemented/)});
test('forwards the selected material and theme tint to the native window',async()=>{
 const {context,sent,reply}=setup();
 const appearance={material:'window-glass',finish:'clear',translucency:65,tint:[15,230,213],light:false};
 const pending=context.__AURALIS_WINUI__.setAppearance(appearance);
 assert.equal(sent[0].command,'set_native_appearance');assert.equal(sent[0].appearance,appearance);
 reply({id:sent[0].id,ok:true,value:{applied:true}});assert.equal((await pending).applied,true);
});
