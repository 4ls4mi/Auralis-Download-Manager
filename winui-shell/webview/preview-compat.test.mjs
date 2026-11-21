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
 assert.match(added.textContent,/cg-material-window-glass[^}]+--native-content-opacity:\.16/);
 assert.match(added.textContent,/cg-material-frosted-water-351[^}]+--native-content-opacity:\.35/);
 assert.match(added.textContent,/cg-material-rose-pine[^}]+--native-content-opacity:\.46/);
 assert.match(added.textContent,/cg-high-contrast[^}]+--native-content-opacity:\.96/);
 assert.doesNotMatch(added.textContent,/:not\(\.cg-material-frosted-water-351\)/);
});

test('preview forwards native window controls and their state',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 for(const [action,command,value] of [['minimize','window_minimize',null],['toggle_maximize','window_toggle_maximize',null],['is_maximized','window_is_maximized',true],['close','window_close',null]]){
  const pending=context.__TAURI_INTERNALS__.invoke('plugin:window|'+action);const message=sent.at(-1);assert.equal(message.command,command);listener({data:{id:message.id,ok:true,value}});assert.equal(await pending,value);
 }
});

test('preview asks the host to open a settings window',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('open_glass_window',{label:'settings',url:'/?settings=1&tab=Appearance',width:968,height:765});
 assert.equal(sent[0].command,'open_glass_window');assert.equal(sent[0].url,'/?settings=1&tab=Appearance');
 listener({data:{id:sent[0].id,ok:true,value:{opened:true}}});assert.equal((await pending).opened,true);
});

test('preview requests real window bounds and display work area',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 for(const [action,command,value] of [['outer_position','window_outer_position',{x:500,y:0}],['outer_size','window_outer_size',{width:700,height:900}],['current_monitor','window_current_monitor',{position:{x:0,y:0},size:{width:1920,height:1080},workArea:{position:{x:0,y:0},size:{width:1920,height:1040}},scaleFactor:1}]]){
  const pending=context.__TAURI_INTERNALS__.invoke('plugin:window|'+action);const message=sent.at(-1);assert.equal(message.command,command);listener({data:{id:message.id,ok:true,value}});assert.equal(await pending,value);
 }
});

test('appearance exports require an explicit host file request',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('export_theme_file',{contents:'{"format":"auralis-theme"}'});assert.equal(sent[0].command,'export_theme_file');listener({data:{id:sent[0].id,ok:true,value:null}});assert.equal(await pending,null);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('export_theme_file',{contents:'x'.repeat(32769)}),/unavailable/);
});

test('native drag and resize requests preserve validated directions',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const drag=context.__TAURI_INTERNALS__.invoke('plugin:window|start_dragging');assert.equal(sent[0].command,'window_start_drag');listener({data:{id:sent[0].id,ok:true,value:null}});await drag;
 const resize=context.__TAURI_INTERNALS__.invoke('plugin:window|start_resize_dragging',{value:'NorthWest'});assert.equal(sent[1].direction,'NorthWest');listener({data:{id:sent[1].id,ok:true,value:null}});await resize;
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('plugin:window|start_resize_dragging',{value:'invalid'}),/unavailable/);
});

test('native movement coalesces interface layout refreshes',async()=>{
 let listener;let refreshes=0;
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage(){}}},window:{dispatchEvent:event=>{assert.equal(event.type,'resize');refreshes++}},Event:class {constructor(type){this.type=type}},setTimeout,clearTimeout};runInNewContext(source,context);
 listener({data:{event:'window_bounds_changed'}});listener({data:{event:'window_bounds_changed'}});
 await new Promise(resolve=>setTimeout(resolve,80));assert.equal(refreshes,1);
});

test('hide-to-tray is requested from the native window',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('plugin:window|hide');assert.equal(sent[0].command,'window_hide');listener({data:{id:sent[0].id,ok:true,value:null}});assert.equal(await pending,null);
});
