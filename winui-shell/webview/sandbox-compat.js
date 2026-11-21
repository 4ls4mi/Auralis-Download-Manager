/* Isolated downloader: no installed user data. */
(() => {
  // Keep the WebView layers translucent enough to reveal the native backdrop,
  // while leaving individual panels readable. This is preview-only CSS.
  if(typeof document!=="undefined")document.addEventListener('DOMContentLoaded',()=>{
    document.documentElement.dataset.auralisWinuiPreview='true';
    const style=document.createElement('style');
    style.textContent=`html[data-auralis-winui-preview] .cg-window.cg-mode-desktop .cg-content{background:linear-gradient(145deg,var(--glass-tint),transparent 70%),rgba(var(--glass),.30)!important;backdrop-filter:none!important}html[data-auralis-winui-preview] .cg-window.cg-mode-desktop .cg-glass{background:rgba(var(--glass),.66)!important;backdrop-filter:none!important}html[data-auralis-winui-preview] .cg-window.cg-mode-desktop :is(.cg-frost-canvas,.cg-frost-fallback){display:none!important}`;
    document.head.append(style);
  });
  const webview=globalThis.chrome?.webview;
  if(!webview)throw new Error('WinUI preview host is unavailable.');
  let nextId=1;const pending=new Map();
  let boundsTimer;
  webview.addEventListener('message',event=>{const m=event.data;if(m?.event==='window_bounds_changed'){if(typeof window!=='undefined' && boundsTimer===undefined)boundsTimer=setTimeout(()=>{boundsTimer=undefined;window.dispatchEvent(new Event('resize'))},50);return}const request=pending.get(m?.id);if(!request)return;pending.delete(m.id);clearTimeout(request.timer);m.ok?request.resolve(m.value):request.reject(new Error(m.error || 'Native request failed.'))});
  const request=(command,args={})=>new Promise((resolve,reject)=>{const id=nextId++;const timer=setTimeout(()=>{pending.delete(id);reject(new Error('Native request timed out.'))},10000);pending.set(id,{resolve,reject,timer});try{webview.postMessage({id,command,...args})}catch(error){pending.delete(id);clearTimeout(timer);reject(error)}});
  const appearance=value=>request('set_native_appearance',{appearance:value});
  // The preview deliberately cannot contact the release push service.
  globalThis.WebSocket=class {constructor(){throw new Error('Network is disabled in visual preview.')}};
  const windowCommands={'plugin:window|minimize':'window_minimize','plugin:window|toggle_maximize':'window_toggle_maximize','plugin:window|close':'window_close','plugin:window|is_maximized':'window_is_maximized','plugin:window|outer_position':'window_outer_position','plugin:window|outer_size':'window_outer_size','plugin:window|current_monitor':'window_current_monitor'};
  const invoke=async(command,args={})=>{
    if(['export_theme_file','export_material_file'].includes(command) && typeof args.contents==='string' && args.contents.length<=32768) return request(command,{contents:args.contents});
    if(command==='clipboard_text')return request(command);
    if(command==='open_glass_window' && typeof args.label==='string' && typeof args.url==='string' && Number.isInteger(args.width) && Number.isInteger(args.height))return request(command,{label:args.label,url:args.url,width:args.width,height:args.height});
    if(command==='boot_engine')return 'Isolated test downloader';
    if(command==='dashboard_snapshot'||command==='dashboard_visuals'||command==='glass_settings')return request(command);
    if(command==='add_download' && typeof args.url==='string' && /^https?:\/\//i.test(args.url.trim()) && typeof args.later==='boolean') return JSON.stringify(await request(command,{url:args.url.trim(),later:args.later}));
    if(command==='queue_action' && typeof args.name==='string' && args.name.length>0 && args.name.length<=256 && ['start_queue','stop_queue'].includes(args.action)) return request(command,{name:args.name,action:args.action});
    if(command==='file_operation' && ['open','folder'].includes(args.operation) && Number.isSafeInteger(args.id) && args.id>0) return request(args.operation==='open'?'file_open':'file_folder',{downloadId:args.id});
    if(command==='file_operation' && args.operation==='speed-limit' && Number.isSafeInteger(args.id) && args.id>0) { const kb=args.value==='off'?0:Number(args.value); if(Number.isInteger(kb) && kb>=0 && kb<=10000000 && (kb>0 || args.value==='off')) return request('file_speed_limit',{downloadId:args.id,value:kb}); }
    if(command==='file_operation' && args.operation==='details' && Number.isSafeInteger(args.id) && args.id>0) return request('file_details',{downloadId:args.id});
    if(command==='download_action' && ['start','pause','remove'].includes(args.action) && Array.isArray(args.ids) && args.ids.length>0 && args.ids.length<=100 && args.ids.every(id=>Number.isSafeInteger(id) && id>0)) {
      const results=await Promise.all([...new Set(args.ids)].map(downloadId=>request(args.action==='start'?'start_download':args.action==='pause'?'pause_download':'remove_download',{downloadId})));
      return {done:results.flatMap(result=>result.done??[]),skipped:results.flatMap(result=>result.skipped??[])};
    }
    if(command==='update_glass_setting' && ['show_complete','show_progress','confirm_delete','double_click_open','max_connections','speed_limit_on','speed_limit_kb','global_limit_on','global_limit_kb','start_immediately','only_add_to_queue'].includes(args.key) && typeof args.value==='string') return request(command,{key:args.key,value:args.value});
    // Disk deletion stays disabled in the isolated test host. The default is already false.
    if(command==='glass_tool' && args.action==='original-setting' && args.payload?.key==='delete_files_too' && args.payload.value===false) return {ok:true};
    if(command==='glass_update_check')return {state:'unavailable'};
    if(command==='backup_prompt_enabled')return false;
    if(command==='browser_connection_status')return {recently_connected:false};
    if(command==='plugin:app|version')return 'visual preview';
    if(command==='plugin:event|listen')return 1;
    if(command==='plugin:event|unlisten'||command==='window_preferences'||command==='set_material_window_shape'||command==='plugin:window|set_effects')return null;
    if(command==='plugin:window|start_dragging')return request('window_start_drag');
    if(command==='plugin:window|start_resize_dragging' && ['North','South','East','West','NorthEast','NorthWest','SouthEast','SouthWest'].includes(args.value))return request('window_start_resize',{direction:args.value});
    if(Object.hasOwn(windowCommands,command))return request(windowCommands[command]);
    throw new Error('This action is unavailable in the isolated visual preview.');
  };
  globalThis.__AURALIS_WINUI__={setAppearance:appearance,isolatedDownloads:true};
  globalThis.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener(){}};
  globalThis.__TAURI_INTERNALS__={invoke,transformCallback(){return 1},unregisterCallback(){},metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},convertFileSrc(){return 'data:,'}};
})();
