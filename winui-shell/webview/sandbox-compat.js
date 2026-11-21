/* Isolated downloader: no installed user data. */
(() => {
  const installed=globalThis.__AURALIS_INSTALLED_HOST__===true;
  // Keep the WebView layers translucent enough to reveal the native backdrop,
  // while leaving individual panels readable. This is preview-only CSS.
  if(typeof document!=="undefined")document.addEventListener('DOMContentLoaded',()=>{
    document.documentElement.dataset.auralisWinuiPreview='true';
    const style=document.createElement('style');
    style.textContent=`
      html[data-auralis-winui-preview] .cg-window.cg-mode-desktop {--native-content-opacity:.30;--native-panel-opacity:.66}
      html[data-auralis-winui-preview] .cg-window.cg-mode-desktop:is(.cg-material-window-glass,.cg-finish-clear) {--native-content-opacity:.16;--native-panel-opacity:.56}
      html[data-auralis-winui-preview] .cg-window.cg-mode-desktop:is(.cg-material-frosted-water-351,.cg-material-builtin-pearl-frost,.cg-finish-frosted) {--native-content-opacity:.35;--native-panel-opacity:.72}
      html[data-auralis-winui-preview] .cg-window.cg-mode-desktop:is(.cg-material-builtin-smoked-glass) {--native-content-opacity:.42;--native-panel-opacity:.76}
      html[data-auralis-winui-preview] .cg-window.cg-mode-desktop:is(.cg-material-rose-pine,.cg-material-oversimplified,.cg-material-builtin-obsidian-matte,.cg-finish-matte) {--native-content-opacity:.46;--native-panel-opacity:.82}
      html[data-auralis-winui-preview] .cg-window.cg-mode-desktop.cg-high-contrast {--native-panel-opacity:.88}
      html[data-auralis-winui-preview] .cg-window.cg-mode-desktop .cg-content{background:linear-gradient(145deg,var(--glass-tint),transparent 70%),rgba(var(--glass),var(--native-content-opacity))!important;backdrop-filter:none!important}
      html[data-auralis-winui-preview] .cg-window.cg-mode-desktop .cg-glass{background:rgba(var(--glass),var(--native-panel-opacity))!important;backdrop-filter:none!important}
      html[data-auralis-winui-preview] .cg-window.cg-mode-desktop :is(.cg-frost-canvas,.cg-frost-fallback){display:none!important}`;
    document.head.append(style);
  });
  const webview=globalThis.chrome?.webview;
  if(!webview)throw new Error('WinUI preview host is unavailable.');
  let nextId=1;const pending=new Map();
  let boundsTimer;
  webview.addEventListener('message',event=>{const m=event.data;if(m?.event==='window_bounds_changed'){if(typeof window!=='undefined' && boundsTimer===undefined)boundsTimer=setTimeout(()=>{boundsTimer=undefined;window.dispatchEvent(new Event('resize'))},50);return}const request=pending.get(m?.id);if(!request)return;pending.delete(m.id);clearTimeout(request.timer);m.ok?request.resolve(m.value):request.reject(new Error(m.error || 'Native request failed.'))});
  // Release checks may use two feeds; native file pickers wait for the user.
  const timeoutFor=command=>command==='update_check'?40000:['export_theme_file','export_material_file','choose_download_path'].includes(command)?300000:10000;
  const request=(command,args={})=>new Promise((resolve,reject)=>{const id=nextId++;const timer=setTimeout(()=>{pending.delete(id);reject(new Error('Native request timed out.'))},timeoutFor(command));pending.set(id,{resolve,reject,timer});try{webview.postMessage({id,command,...args})}catch(error){pending.delete(id);clearTimeout(timer);reject(error)}});
  const appearance=value=>request('set_native_appearance',{appearance:value});
  // The preview deliberately cannot contact the release push service.
  globalThis.WebSocket=class {constructor(){throw new Error('Network is disabled in visual preview.')}};
  const windowCommands={'plugin:window|hide':'window_hide','plugin:window|minimize':'window_minimize','plugin:window|toggle_maximize':'window_toggle_maximize','plugin:window|close':'window_close','plugin:window|is_maximized':'window_is_maximized','plugin:window|outer_position':'window_outer_position','plugin:window|outer_size':'window_outer_size','plugin:window|current_monitor':'window_current_monitor'};
  const invoke=async(command,args={})=>{
    if(['export_theme_file','export_material_file'].includes(command) && typeof args.contents==='string' && args.contents.length<=32768) return request(command,{contents:args.contents});
    if(installed && command==='choose_download_path' && typeof args.current==='string' && args.current.length<=4096 && !args.current.includes('\0'))return request(command,{current:args.current});
    if(installed && command==='startup_settings')return request(command);
    if(installed && command==='set_startup_settings' && typeof args.enabled==='boolean' && ['window','minimized'].includes(args.mode))return request(command,{enabled:args.enabled,mode:args.mode});
    if(command==='clipboard_text')return request(command);
    if(command==='open_glass_window' && typeof args.label==='string' && typeof args.url==='string' && Number.isInteger(args.width) && Number.isInteger(args.height))return request(command,{label:args.label,url:args.url,width:args.width,height:args.height});
    if(command==='window_preferences' && typeof args.autoProgress==='boolean')return request('progress_preferences',{enabled:args.autoProgress});
    if(command==='hidden_progress_window_ids')return request('progress_ids');
    if(['hide_download_to_tray','restore_hidden_progress_window'].includes(command) && Number.isSafeInteger(args.id) && args.id>0)return request(command==='hide_download_to_tray'?'progress_hide':'progress_restore',{downloadId:args.id});
    if(command==='plugin:window|available_monitors'){const monitor=await request('window_current_monitor');return monitor?[monitor]:[];}
    if(command==='boot_engine')return installed?'Auralis integrated downloader':'Isolated test downloader';
    if(command==='dashboard_snapshot'||command==='dashboard_visuals'||command==='glass_settings')return request(command);
    if(command==='list_network_adapters')return request('network_adapters');
    if(command==='glass_tool' && args.action==='original-settings')return request('preferences');
    if(command==='glass_tool' && args.action==='queues')return request('queue_schedules');
    if(command==='glass_tool' && args.action==='schedule' && args.payload && typeof args.payload==='object')return request('save_schedule',{payload:args.payload});
    if(command==='glass_tool' && args.action==='original-setting') {
      const {key,value,clear=false}=args.payload??{};
      if((['limiter_on_startup','global_only_active','set_creation_date','mark_downloads','ignore_mtime','many_connections','proxy_http','proxy_https','proxy_ftp','dns_fallback','ftp_passive'].includes(key) && typeof value==='boolean') ||
         (['duplicate_action','proxy_mode','dns_mode'].includes(key) && Number.isInteger(value) && value>=0 && value<=3) ||
         (['proxy_script','proxy_host','proxy_port','proxy_user','proxy_pass','user_agent','dns_provider','dns_servers','dns_tls_name','dns_doh_url','dns_nextdns_id'].includes(key) && typeof value==='string' && value.length<=512 && !value.includes('\0'))) {
        if(typeof clear==='boolean' && (!clear || key==='proxy_pass')) return request('update_preference',{key,value,clear});
      }
    }
    if(command==='add_download' && typeof args.url==='string' && (installed?/^(?:https?|ftp):\/\//i:/^https?:\/\//i).test(args.url.trim()) && typeof args.later==='boolean') return JSON.stringify(await request(command,{url:args.url.trim(),later:args.later}));
    if(installed && command==='pending_file_info')return request('pending_file_info');
    if(installed && command==='file_info_action' && Number.isSafeInteger(args.id) && args.id>0 && ['commit','cancel','category'].includes(args.action) && (args.payload===null || typeof args.payload==='object')) return request('file_info_action',{downloadId:args.id,action:args.action,payload:args.payload});
    if(command==='queue_action' && typeof args.name==='string' && args.name.length>0 && args.name.length<=256 && ['start_queue','stop_queue'].includes(args.action)) return request(command,{name:args.name,action:args.action});
    if(command==='file_operation' && ['open','open-with','folder'].includes(args.operation) && Number.isSafeInteger(args.id) && args.id>0) return request(args.operation==='open'?'file_open':args.operation==='open-with'?'file_open_with':'file_folder',{downloadId:args.id});
    if(command==='file_operation' && args.operation==='speed-limit' && Number.isSafeInteger(args.id) && args.id>0) { const kb=args.value==='off'?0:Number(args.value); if(Number.isInteger(kb) && kb>=0 && kb<=10000000 && (kb>0 || args.value==='off')) return request('file_speed_limit',{downloadId:args.id,value:kb}); }
    if(command==='file_operation' && args.operation==='details' && Number.isSafeInteger(args.id) && args.id>0) return request('file_details',{downloadId:args.id});
    if(command==='file_operation' && ['check-saved','check-saved-result'].includes(args.operation) && Number.isSafeInteger(args.id) && args.id>0) return request(args.operation==='check-saved'?'check_saved':'check_saved_result',{downloadId:args.id});
    if(command==='file_operation' && args.operation==='checksum-result' && Number.isSafeInteger(args.id) && args.id>0) return request('checksum_result',{downloadId:args.id});
    if(command==='file_operation' && args.operation==='checksum' && Number.isSafeInteger(args.id) && args.id>0 && typeof args.value==='string' && /^[\x20-\x7e]{1,256}$/.test(args.value)) return request('checksum',{downloadId:args.id,value:args.value});
    if(command==='file_operation' && args.operation==='refresh-address' && Number.isSafeInteger(args.id) && args.id>0 && typeof args.value==='string' && /^https?:\/\//i.test(args.value) && args.value.length<=8192) return request('refresh_address',{downloadId:args.id,value:args.value});
    if(command==='file_operation' && args.operation==='queue-add' && Number.isSafeInteger(args.id) && args.id>0 && typeof args.value==='string' && args.value.length>0 && args.value.length<=256) return request('queue_item_add',{downloadId:args.id,name:args.value});
    if(command==='file_operation' && args.operation==='queue-remove' && Number.isSafeInteger(args.id) && args.id>0) return request('queue_item_remove',{downloadId:args.id});
    if(command==='download_action' && ['start','pause','remove'].includes(args.action) && Array.isArray(args.ids) && args.ids.length>0 && args.ids.length<=100 && args.ids.every(id=>Number.isSafeInteger(id) && id>0)) {
      const results=await Promise.all([...new Set(args.ids)].map(downloadId=>request(args.action==='start'?'start_download':args.action==='pause'?'pause_download':'remove_download',{downloadId})));
      return {done:results.flatMap(result=>result.done??[]),skipped:results.flatMap(result=>result.skipped??[])};
    }
    if(command==='update_glass_setting' && ['show_complete','show_progress','confirm_delete','double_click_open','max_connections','speed_limit_on','speed_limit_kb','global_limit_on','global_limit_kb','start_immediately','only_add_to_queue','net_adapter'].includes(args.key) && typeof args.value==='string') return request(command,{key:args.key,value:args.value});
    // Disk deletion stays disabled in the isolated test host. The default is already false.
    if(command==='glass_tool' && args.action==='original-setting' && args.payload?.key==='delete_files_too' && args.payload.value===false) return {ok:true};
    if(command==='glass_update_check')return request('update_check');
    if(command==='backup_prompt_enabled')return false;
    if(command==='browser_connection_status')return {recently_connected:false};
    if(command==='plugin:app|version')return request('app_version');
    if(command==='plugin:event|listen')return 1;
    if(command==='plugin:event|unlisten'||command==='set_material_window_shape'||command==='plugin:window|set_effects')return null;
    if(command==='plugin:window|start_dragging')return request('window_start_drag');
    if(command==='plugin:window|start_resize_dragging' && ['North','South','East','West','NorthEast','NorthWest','SouthEast','SouthWest'].includes(args.value))return request('window_start_resize',{direction:args.value});
    if(Object.hasOwn(windowCommands,command))return request(windowCommands[command]);
    throw new Error('This action is unavailable in the isolated visual preview.');
  };
  globalThis.__AURALIS_WINUI__={setAppearance:appearance,isolatedDownloads:!installed,updateInstallSupported:false,supportsComputerActions:false,limitedPreferences:true,usesNativeUpdateNotifications:true,notifyUpdate:version=>request('notify_update',{version})};
  globalThis.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener(){}};
  globalThis.__TAURI_INTERNALS__={invoke,transformCallback(){return 1},unregisterCallback(){},metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},convertFileSrc(){return 'data:,'}};
})();
