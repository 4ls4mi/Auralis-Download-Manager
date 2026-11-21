import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
const source=readFileSync(new URL('./sandbox-compat.js',import.meta.url),'utf8');
test('isolated preferences expose only validated scalar updates',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const read=context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-settings'});assert.equal(sent[0].command,'preferences');
 listener({data:{id:sent[0].id,ok:true,value:{fields:[]}}});await read;
 const save=context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-setting',payload:{key:'many_connections',value:true}});
 assert.equal(sent[1].command,'update_preference');assert.equal(sent[1].value,true);
 listener({data:{id:sent[1].id,ok:true,value:{ok:true}}});await save;
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-setting',payload:{key:'site_logins',value:'secret'}}),/unavailable/);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-setting',payload:{key:'duplicate_action',value:4}}),/unavailable/);
 const proxy=context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-setting',payload:{key:'proxy_host',value:'proxy.example.test'}});
 assert.equal(sent[2].key,'proxy_host');listener({data:{id:sent[2].id,ok:true,value:{ok:true}}});await proxy;
 const clear=context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-setting',payload:{key:'proxy_pass',value:'',clear:true}});
 assert.equal(sent[3].key,'proxy_pass');assert.equal(sent[3].clear,true);listener({data:{id:sent[3].id,ok:true,value:{ok:true}}});await clear;
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-setting',payload:{key:'proxy_host',value:'',clear:true}}),/unavailable/);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-setting',payload:{key:'proxy_mode',value:5}}),/unavailable/);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-setting',payload:{key:'proxy_host',value:'x'.repeat(513)}}),/unavailable/);
});
test('release fallback and file pickers have time to complete',async()=>{
 let listener;const sent=[],timeouts=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout:(_fn,delay)=>{timeouts.push(delay);return timeouts.length},clearTimeout(){}};runInNewContext(source,context);
 for(const [command,args,delay] of [['glass_update_check',{},40000],['export_theme_file',{contents:'{}'},300000],['dashboard_snapshot',{},10000]]){
  const pending=context.__TAURI_INTERNALS__.invoke(command,args);assert.equal(timeouts.at(-1),delay);
  listener({data:{id:sent.at(-1).id,ok:true,value:{}}});await pending;
 }
});
test('sandbox restricts downloader requests and allows isolated display preferences',async()=>{
 let listener;const messages=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>messages.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('dashboard_snapshot');assert.equal(messages[0].command,'dashboard_snapshot');listener({data:{id:messages[0].id,ok:true,value:{downloads:[]}}});assert.equal((await pending).downloads.length,0);
 const setting=context.__TAURI_INTERNALS__.invoke('update_glass_setting',{key:'show_complete',value:'false'});assert.equal(messages[1].key,'show_complete');listener({data:{id:messages[1].id,ok:true,value:{saved:true}}});assert.equal((await setting).saved,true);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('update_glass_setting',{key:'advanced_integration',value:'true'}),/unavailable/);
 const action=context.__TAURI_INTERNALS__.invoke('download_action',{action:'start',ids:[1]});assert.equal(messages[2].command,'start_download');listener({data:{id:messages[2].id,ok:true,value:{done:[1]}}});assert.equal((await action).done[0],1);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('download_action',{action:'delete',ids:[1]}),/unavailable/);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('add_download',{url:'magnet:?xt=urn:btih:123',later:false}),/unavailable/);
 assert.throws(()=>new context.WebSocket('wss://example.com'),/disabled/);
});

test('isolated downloader uses native window controls',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const result=context.__TAURI_INTERNALS__.invoke('plugin:window|is_maximized');assert.equal(sent[0].command,'window_is_maximized');listener({data:{id:sent[0].id,ok:true,value:true}});assert.equal(await result,true);
});

test('isolated downloader asks the host to open a progress window',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('open_glass_window',{label:'download-1',url:'/?detail=1',width:760,height:560});
 assert.equal(sent[0].command,'open_glass_window');assert.equal(sent[0].label,'download-1');
 listener({data:{id:sent[0].id,ok:true,value:{opened:true}}});assert.equal((await pending).opened,true);
});

test('progress windows may read details but cannot request file operations',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'details',value:null});assert.equal(sent[0].command,'file_details');assert.equal(sent[0].downloadId,7);
 listener({data:{id:sent[0].id,ok:true,value:{own_limit_kb:null}}});assert.equal((await pending).own_limit_kb,null);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'open-with',value:null}),/unavailable/);
});

test('saved-data checking uses only the download ID and does not expose repair or torrent actions',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 for(const [operation,command,value] of [['check-saved','check_saved',{pending:true}],['check-saved-result','check_saved_result',{complete:true,report:{checked_bytes:10,unhashed_bytes:0,damaged_ranges:[]}}]]){
  const pending=context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation,value:'/outside'});const message=sent.at(-1);
  assert.equal(message.command,command);assert.equal(message.downloadId,7);assert.equal('value' in message,false);
  listener({data:{id:message.id,ok:true,value}});assert.deepEqual(await pending,value);
 }
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'repair-saved'}),/unavailable/);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'find-recovery-torrents'}),/unavailable/);
});

test('completed-file checksum checks use a bounded value and the download ID',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const start=context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'checksum',value:'a'.repeat(64)});
 assert.equal(sent[0].command,'checksum');assert.equal(sent[0].downloadId,7);
 listener({data:{id:sent[0].id,ok:true,value:{pending:true}}});assert.equal((await start).pending,true);
 const poll=context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'checksum-result'});
 assert.equal(sent[1].command,'checksum_result');listener({data:{id:sent[1].id,ok:true,value:{complete:true,matches:true}}});assert.equal((await poll).matches,true);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'checksum',value:'x'.repeat(257)}),/unavailable/);
});

test('refreshing an address accepts only HTTP or HTTPS and preserves the download ID',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'refresh-address',value:'https://example.test/new'});
 assert.equal(sent[0].command,'refresh_address');assert.equal(sent[0].downloadId,7);
 listener({data:{id:sent[0].id,ok:true,value:{ok:true}}});assert.equal((await pending).ok,true);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'refresh-address',value:'file:///outside'}),/unavailable/);
});

test('multiple selected downloads preserve each start result',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('download_action',{action:'start',ids:[1,2,1]});assert.equal(sent.length,2);
 listener({data:{id:sent[0].id,ok:true,value:{done:[1],skipped:[]}}});listener({data:{id:sent[1].id,ok:true,value:{done:[],skipped:[{id:2,reason:'already started'}]}}});
 const result=await pending;assert.deepEqual(Array.from(result.done),[1]);assert.equal(result.skipped[0].id,2);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('download_action',{action:'start',ids:Array(101).fill(1)}),/unavailable/);
});

test('speed limits are bounded before reaching the test downloader',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'speed-limit',value:'512'});assert.equal(sent[0].value,512);listener({data:{id:sent[0].id,ok:true,value:{ok:true}}});assert.equal((await pending).ok,true);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'speed-limit',value:'10000001'}),/unavailable/);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'speed-limit',value:'0'}),/unavailable/);
});

test('queue controls are limited to start and stop in the isolated engine',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('queue_action',{name:'Main download queue',action:'start_queue'});assert.equal(sent[0].action,'start_queue');listener({data:{id:sent[0].id,ok:true,value:{done:[],skipped:[]}}});assert.equal((await pending).done.length,0);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('queue_action',{name:'Main download queue',action:'delete_queue'}),/unavailable/);
});

test('a test download can be added to or removed from an existing queue',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const add=context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'queue-add',value:'Main download queue'});
 assert.equal(sent[0].command,'queue_item_add');assert.equal(sent[0].downloadId,7);assert.equal(sent[0].name,'Main download queue');
 listener({data:{id:sent[0].id,ok:true,value:{ok:true}}});await add;
 const remove=context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'queue-remove',value:'/outside'});
 assert.equal(sent[1].command,'queue_item_remove');assert.equal('value' in sent[1],false);
 listener({data:{id:sent[1].id,ok:true,value:{ok:true}}});await remove;
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation:'queue-add',value:''}),/unavailable/);
});

test('add URL dialog forwards only HTTP test downloads and receives the existing UI response shape',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('add_download',{url:' https://example.com/file ',later:false});
 assert.equal(sent[0].command,'add_download');assert.equal(sent[0].url,'https://example.com/file');
 listener({data:{id:sent[0].id,ok:true,value:{pending:true}}});assert.equal(JSON.parse(await pending).pending,true);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('add_download',{url:'file:///etc/passwd',later:false}),/unavailable/);
});

test('remove is available without exposing delete-file actions',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('download_action',{action:'remove',ids:[7]});assert.equal(sent[0].command,'remove_download');listener({data:{id:sent[0].id,ok:true,value:{done:[7],skipped:[]}}});assert.equal((await pending).done[0],7);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('download_action',{action:'delete',ids:[7]}),/unavailable/);
});

test('list removal keeps the isolated no-disk-deletion preference',async()=>{
 const context={chrome:{webview:{addEventListener(){},postMessage(){}}},setTimeout,clearTimeout};runInNewContext(source,context);
 assert.equal((await context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-setting',payload:{key:'delete_files_too',value:false}})).ok,true);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('glass_tool',{action:'original-setting',payload:{key:'delete_files_too',value:true}}),/unavailable/);
});

test('isolated connection settings can be adjusted without enabling browser integration',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('update_glass_setting',{key:'max_connections',value:'8'});assert.equal(sent[0].key,'max_connections');listener({data:{id:sent[0].id,ok:true,value:{saved:true}}});assert.equal((await pending).saved,true);
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('update_glass_setting',{key:'proxy_from_browser',value:'true'}),/unavailable/);
});

test('network adapter selection is sent to the isolated downloader',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const list=context.__TAURI_INTERNALS__.invoke('list_network_adapters');assert.equal(sent[0].command,'network_adapters');
 listener({data:{id:sent[0].id,ok:true,value:{adapters:[{name:'Test VPN',address:'127.0.0.1'}]}}});assert.equal((await list).adapters[0].name,'Test VPN');
 const save=context.__TAURI_INTERNALS__.invoke('update_glass_setting',{key:'net_adapter',value:'Test VPN'});assert.equal(sent[1].key,'net_adapter');
 listener({data:{id:sent[1].id,ok:true,value:{saved:true}}});assert.equal((await save).saved,true);
});

test('file actions send only an ID to the host, never a web supplied path',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 for(const [operation,command] of [['open','file_open'],['folder','file_folder']]){
  const pending=context.__TAURI_INTERNALS__.invoke('file_operation',{id:7,operation,value:'C:\\outside.exe'});const message=sent.at(-1);assert.equal(message.command,command);assert.equal(message.downloadId,7);assert.equal('value' in message,false);listener({data:{id:message.id,ok:true,value:{ok:true}}});await pending;
 }
});

test('clipboard text is only requested when the interface asks for it',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 assert.equal(sent.length,0);const pending=context.__TAURI_INTERNALS__.invoke('clipboard_text');assert.equal(sent[0].command,'clipboard_text');listener({data:{id:sent[0].id,ok:true,value:'https://example.com/file'}});assert.equal(await pending,'https://example.com/file');
});

test('hidden progress tray controls use IDs and support restoring a window',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 for(const [command,args,native,value] of [['hide_download_to_tray',{id:9},'progress_hide',null],['hidden_progress_window_ids',{},'progress_ids',[9]],['restore_hidden_progress_window',{id:9},'progress_restore',null]]){
  const pending=context.__TAURI_INTERNALS__.invoke(command,args);const message=sent.at(-1);assert.equal(message.command,native);listener({data:{id:message.id,ok:true,value}});assert.equal(await pending,value);
 }
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('hide_download_to_tray',{id:-1}),/unavailable/);
});

test('automatic progress-window preference is forwarded to the native host',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('window_preferences',{autoProgress:false});assert.equal(sent[0].command,'progress_preferences');assert.equal(sent[0].enabled,false);listener({data:{id:sent[0].id,ok:true,value:null}});assert.equal(await pending,null);
});

test('the development shell requests a release check through the validated host',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 const pending=context.__TAURI_INTERNALS__.invoke('glass_update_check');assert.equal(sent[0].command,'update_check');listener({data:{id:sent[0].id,ok:true,value:{state:'latest'}}});assert.equal((await pending).state,'latest');
 await assert.rejects(context.__TAURI_INTERNALS__.invoke('glass_update_install'),/unavailable/);
});

test('the Windows notification is requested only for the chosen update presentation',async()=>{
 let listener;const sent=[];
 const context={chrome:{webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:m=>sent.push(m)}},setTimeout,clearTimeout};runInNewContext(source,context);
 assert.equal(sent.length,0);const pending=context.__AURALIS_WINUI__.notifyUpdate('0.3.49');assert.equal(sent[0].command,'notify_update');assert.equal(sent[0].version,'0.3.49');listener({data:{id:sent[0].id,ok:true,value:{shown:true}}});assert.equal((await pending).shown,true);
});
