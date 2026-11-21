/* Isolated visual preview: no engine, user data, download actions or network. */
(() => {
  // Keep the WebView layers translucent enough to reveal the native backdrop,
  // while leaving individual panels readable. This is preview-only CSS.
  if(typeof document!=="undefined")document.addEventListener('DOMContentLoaded',()=>{
    document.documentElement.dataset.auralisWinuiPreview='true';
    const style=document.createElement('style');
    style.textContent=`html[data-auralis-winui-preview] .cg-window.cg-mode-desktop:not(.cg-material-frosted-water-351) .cg-content{background:linear-gradient(145deg,var(--glass-tint),transparent 70%),rgba(var(--glass),.30)!important;backdrop-filter:none!important}html[data-auralis-winui-preview] .cg-window.cg-mode-desktop .cg-glass{background:rgba(var(--glass),.66)!important;backdrop-filter:none!important}`;
    document.head.append(style);
  });
  const webview=globalThis.chrome?.webview;
  if(!webview)throw new Error('WinUI preview host is unavailable.');
  let nextId=1;const pending=new Map();
  webview.addEventListener('message',event=>{const m=event.data,request=pending.get(m?.id);if(!request)return;pending.delete(m.id);clearTimeout(request.timer);m.ok?request.resolve(m.value):request.reject(new Error('Native backdrop could not be applied.'))});
  const appearance=value=>new Promise((resolve,reject)=>{const id=nextId++;const timer=setTimeout(()=>{pending.delete(id);reject(new Error('Native backdrop request timed out.'))},5000);pending.set(id,{resolve,reject,timer});try{webview.postMessage({id,command:'set_native_appearance',appearance:value})}catch(error){pending.delete(id);clearTimeout(timer);reject(error)}});
  // The preview deliberately cannot contact the release push service.
  globalThis.WebSocket=class {constructor(){throw new Error('Network is disabled in visual preview.')}};
  const empty={downloads:[],queues:[],categories:[],speed:0};
  const invoke=async(command)=>{
    if(command==='boot_engine')return 'Visual preview — downloader disabled';
    if(command==='dashboard_snapshot')return empty;
    if(command==='dashboard_visuals')return {downloads:[]};
    if(command==='glass_update_check')return {state:'unavailable'};
    if(command==='glass_settings')return {double_click_open:false,confirm_delete:true,delete_files_too:false};
    if(command==='backup_prompt_enabled')return false;
    if(command==='browser_connection_status')return {recently_connected:true};
    if(command==='plugin:app|version')return 'visual preview';
    if(command==='plugin:event|listen')return 1;
    if(command==='plugin:event|unlisten'||command==='window_preferences'||command==='set_material_window_shape'||command==='plugin:window|set_effects')return null;
    if(command==='plugin:window|is_maximized')return false;
    if(command==='plugin:window|outer_position')return {x:0,y:0};
    if(command==='plugin:window|outer_size')return {width:960,height:690};
    if(command==='plugin:window|current_monitor')return null;
    throw new Error('This action is unavailable in the isolated visual preview.');
  };
  globalThis.__AURALIS_WINUI__={setAppearance:appearance};
  globalThis.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener(){}};
  globalThis.__TAURI_INTERNALS__={invoke,transformCallback(){return 1},unregisterCallback(){},metadata:{currentWindow:{label:'main'},currentWebview:{label:'main'}},convertFileSrc(){return 'data:,'}};
})();
