import {savePreferences,restorePreferences} from "./preferencesBackup";
import { liquidMaterials } from "./LiquidIndicators";
import {loadMaterials,materialId,materialPresets,extraMaterials,parseMaterial,MATERIALS_KEY} from "./customMaterials";
import {loadThemes,parseTheme,paletteForTheme,themeId,THEMES_KEY,type ThemeFile,type ThemeSettings} from "./themeFiles";
import { listen } from "@tauri-apps/api/event";
import CrystalAccounts from "./CrystalAccounts";
import CrystalHelpers from "./CrystalHelpers";
import CrystalUpstream from "./CrystalUpstream";
import CrystalOriginalSettings from "./CrystalOriginalSettings";
import { useEffect, useState, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getVersion } from "@tauri-apps/api/app";
import { Activity, Check, CheckCircle2, Download, Folder, Gauge, Globe2, Image, Network, Palette, RotateCcw, Settings, SlidersHorizontal } from "lucide-react";
import { CrystalWindow, WindowTop, GradientBar, SpeedGraph, ConnectionMap, themes, themeHue, indicatorPalettes, useCrystal, openWindow } from "./CrystalShared";
import type { Appearance, BackgroundMode, Queue } from "./CrystalShared";

type EngineSettings = {
  max_connections:number;speed_limit_on:boolean;speed_limit_kb:number;global_limit_on:boolean;
  global_limit_kb:number;start_immediately:boolean;only_add_to_queue:boolean;confirm_delete:boolean;
  torrent_keep_sharing:boolean;torrent_dht:boolean;torrent_lsd:boolean;torrent_recovery_mode?:string;
  proxy_from_browser:boolean;capture_opened:boolean;advanced_integration:boolean;
  show_complete:boolean;show_progress:boolean;double_click_open:boolean;
  category_dirs:[string,string][];net_adapter:string
};
type EngineKey=keyof EngineSettings;
type Tab="General"|"Downloads"|"Connection"|"Browser Integration"|"Torrents"|"Scheduler"|"Accounts"|"Appearance"|"Advanced";
const tabs:{name:Tab;icon:typeof Settings}[]=[
  {name:"General",icon:Settings},{name:"Downloads",icon:Download},
  {name:"Connection",icon:Network},{name:"Browser Integration",icon:Globe2},
  {name:"Torrents",icon:Activity},{name:"Scheduler",icon:Gauge},
  {name:"Accounts",icon:Globe2},{name:"Appearance",icon:Palette},{name:"Advanced",icon:SlidersHorizontal}
];
export default function CrystalSettings(){
  const initial=new URLSearchParams(location.search).get("tab") as Tab|null;
  const [tab,setTab]=useState<Tab>(tabs.some(t=>t.name===initial)?initial!:"General");
  const [settingsPanel,setSettingsPanel]=useState(new URLSearchParams(location.search).get("panel")==="Updates"?"Updates":"Main options");
  useEffect(()=>{let unlisten:(()=>void)|undefined; let active=true;
    void listen<string>("glass-navigate",event=>{const route=new URLSearchParams(event.payload);const target=route.get("tab") as Tab|null;if(target&&tabs.some(t=>t.name===target)){setTab(target);setSettingsPanel(route.get("panel")==="Updates"?"Updates":"Main options");}}).then(stop=>{if(active)unlisten=stop;else stop()});
    return ()=>{active=false;unlisten?.()};
  },[]);
  const [appearanceTab,setAppearanceTab]=useState("Appearance");
  const [customMaterials,setCustomMaterials]=useState(loadMaterials);
  const [customThemes,setCustomThemes]=useState(loadThemes);
  useEffect(()=>{const update=(e:StorageEvent)=>{if(!e.key||e.key===THEMES_KEY)setCustomThemes(loadThemes())};window.addEventListener('storage',update);return()=>window.removeEventListener('storage',update)},[]);
  useEffect(()=>{const update=(e:StorageEvent)=>{if(!e.key||e.key===MATERIALS_KEY)setCustomMaterials(loadMaterials())};window.addEventListener('storage',update);return()=>window.removeEventListener('storage',update)},[]);
  const [indicatorTab,setIndicatorTab]=useState("Progress");
  const [cfg,setCfg]=useState<EngineSettings|null>(null);
  const [queues,setQueues]=useState<Queue[]>([]);
  const [busy,setBusy]=useState(false),[error,setError]=useState(""),[notice,setNotice]=useState("");
  const [browser,setBrowser]=useState("");
  const [appVersion,setAppVersion]=useState("");
  const [updatePresentation,setUpdatePresentation]=useState(()=>localStorage.getItem("auralis-update-presentation")||"quiet");
  const [startup,setStartup]=useState<{enabled:boolean;mode:string}|null>(null);
  const [adapters,setAdapters]=useState<{name:string;address:string|null}[]>([]);
  const [adapterError,setAdapterError]=useState("");
  useEffect(()=>{void invoke<{enabled:boolean;mode:string}>("startup_settings").then(setStartup).catch(e=>setError("Could not read Windows startup settings: "+String(e)))},[]);
  const changeStartup=async(enabled:boolean,mode:string)=>{setBusy(true);setError("");setNotice("");try{setStartup(await invoke<{enabled:boolean;mode:string}>("set_startup_settings",{enabled,mode}));setNotice("Saved.")}catch(e){setError("Could not update Windows startup: "+String(e))}finally{setBusy(false)}};
  useEffect(()=>{void getVersion().then(setAppVersion).catch(()=>setAppVersion("unavailable"))},[]);
  useEffect(()=>{if(tab!=="Connection"&&!(tab==="Advanced"&&settingsPanel==="Updates"))return;let active=true;void invoke<{adapters:{name:string;address:string|null}[]}>("list_network_adapters").then(result=>{if(active){setAdapters(result.adapters);setAdapterError("")}}).catch(e=>{if(active)setAdapterError(String(e))});return()=>{active=false}},[tab,settingsPanel]);
  const adapterPicker=()=>cfg&&<label className="cg-field">Preferred network adapter<select value={cfg.net_adapter} disabled={busy||Boolean(adapterError)} onChange={e=>void change("net_adapter",e.target.value)}><option value="">Automatic — Windows chooses</option>{cfg.net_adapter&&!adapters.some(a=>a.name===cfg.net_adapter)&&<option value={cfg.net_adapter}>{cfg.net_adapter} (not connected)</option>}{adapters.map(a=><option key={a.name} value={a.name}>{a.name} {a.address?`— ${a.address}`:"(not connected)"}</option>)}</select><small>Choose Automatic unless you need to route downloads through a specific adapter or VPN. Downloads may stop if that adapter disconnects.</small>{adapterError&&<small>Unable to list adapters: {adapterError}</small>}</label>;

  const [connection,setConnection]=useState<{recently_connected:boolean;previously_connected:boolean}|null>(null);
  const {appearance,theme,set}=useCrystal();
  const applyTheme=(file:ThemeFile)=>{
    const material=file.customMaterial;
    if(material){const existing=loadMaterials();const sameName=existing.find(m=>materialId(m)===materialId(material));if(sameName&&JSON.stringify(sameName)!==JSON.stringify(material))throw Error('A different custom material already has this name. Rename customMaterial.name in the theme file.');const updated=[...existing.filter(m=>materialId(m)!==materialId(material)),material];if(updated.length>32)throw Error('A maximum of 32 custom materials is supported.');localStorage.setItem(MATERIALS_KEY,JSON.stringify(updated));setCustomMaterials(updated)}
    set('material',material?materialId(material):file.material);
    for(const [key,value] of Object.entries(file.settings)){set(key as keyof Appearance,value as Appearance[keyof Appearance])}
    set('tintHue',themeHue(paletteForTheme(file.palette)));
    set('theme',themeId(file.palette));
  };
  const exportTheme=async()=>{
    const custom=customMaterials.find(m=>materialId(m)===appearance.material)??null;
    const settingsKeys:(keyof ThemeSettings)[]=['tintStrength','fontFamily','fontSize','highContrast','uiScale','dim','blur','indicator','connectionIndicator','graphIndicator','progressMaterial','connectionMaterial','graphMaterial','progressShape','connectionShape','graphShape','trackFinish','trackColor','connectionTrackFinish','connectionTrackColor'];
    const settings=Object.fromEntries(settingsKeys.map(key=>[key,appearance[key]]));
    const data=parseTheme({format:'auralis-theme',version:1,palette:{name:theme.name,accent:theme.accent,secondary:theme.secondary,surface:theme.neutralTint??null,light:theme.light===true||theme.id==='white-frost'||theme.id==='white-pearl'},material:custom?'custom':appearance.material,customMaterial:custom,settings});
    const file=await invoke<string|null>('export_theme_file',{contents:JSON.stringify(data,null,2)+'\n'});if(file)setNotice('Theme exported. Edit the JSON file and import it here.');
  };
  const load=useCallback(async()=>{
    try{
      const [settings,data]=await Promise.all([
        invoke<EngineSettings>("glass_settings"),
        invoke<{queues:Queue[]}>("dashboard_snapshot")
      ]);
      setCfg(settings);setQueues(data.queues??[]);
    }catch(e){setError("The download service is unavailable: "+String(e))}
  },[]);
  useEffect(()=>{void load();void invoke<string>("browser_integration",{repair:false}).then(setBrowser).catch(e=>setBrowser(String(e)))},[load]);
  useEffect(()=>{if(tab!=="Browser Integration")return;let active=true;const check=()=>void invoke<{recently_connected:boolean;previously_connected:boolean}>("browser_connection_status").then(v=>{if(active)setConnection(v)}).catch(()=>{if(active)setConnection(null)});check();const timer=setInterval(check,5000);return()=>{active=false;clearInterval(timer)}},[tab]);
  const change=async(key:EngineKey,value:boolean|number|string)=>{
    setBusy(true);setError("");setNotice("");
    const previous=cfg;setCfg(old=>old?{...old,[key]:value}:old);
    try{
      await invoke("update_glass_setting",{key,value:String(value)});
      const result=await invoke<EngineSettings>("glass_settings");
      setCfg(result);setNotice("Saved.");
    }catch(e){setCfg(previous);setError(String(e))}finally{setBusy(false)}
  };
  const check=(key:EngineKey,title:string,detail:string)=>
    <label className="cg-toggle" key={key}><span><strong>{title}</strong><small>{detail}</small></span>
      <input type="checkbox" disabled={!cfg||busy} checked={Boolean(cfg?.[key])} onChange={e=>void change(key,e.target.checked)}/></label>;
  const number=(key:EngineKey,title:string,detail:string,min:number,max:number)=>
    <label className="cg-toggle" key={key}><span><strong>{title}</strong><small>{detail}</small></span>
      <input type="number" style={{width:105,padding:8,borderRadius:9,background:"rgba(0,0,0,.21)",border:"1px solid rgba(200,240,250,.2)"}}
        min={min} max={max} disabled={!cfg||busy} key={String(cfg?.[key])}
        defaultValue={Number(cfg?.[key]??0)}
        onBlur={e=>{const v=Number(e.target.value);if(Number.isInteger(v)&&v>=min&&v<=max&&v!==cfg?.[key])void change(key,v);else if(v<min||v>max)setError(`${title} must be between ${min} and ${max}.`)}}/></label>;
  const mode=(target:"main"|"details")=>{
    const current=target==="main"?appearance.mainMode:appearance.detailMode;
    const key: keyof Appearance=target==="main"?"mainMode":"detailMode";
    return <div className="cg-glass" style={{padding:13,margin:"12px 0"}}>
      <strong>{target==="main"?"Main window background":"Download and other popup backgrounds"}</strong>
      <div className="cg-wall-choice">{(["desktop","wallpaper","solid"] as BackgroundMode[]).map(m=>
        <button key={m} className={`cg-btn ${current===m?"cg-btn-primary":""}`} onClick={()=>set(key,m)}>
          {m==="desktop"?"See-through desktop":m==="wallpaper"?"Custom wallpaper":"Solid color"}
        </button>)}
      </div>
      <button className="cg-btn" onClick={async()=>{
        try{
          const file=await invoke<string|null>("select_wallpaper",{target});
          if(file){if(target==="main")set("wallMain",file);else set("wallDetail",file);set(key,"wallpaper")}
        }catch(e){setError(String(e))}
      }}><Image size={15}/> Choose image or video</button>
      <button className="cg-btn" style={{marginLeft:8}} onClick={()=>{
        if(target==="main")set("wallMain","");else set("wallDetail","");
        set(key,"desktop");
      }}>Remove wallpaper</button>
      <p>{target==="main"?appearance.wallMain||"Default Alpine wallpaper":appearance.wallDetail||"Inherits main wallpaper if none selected"}</p>
    </div>;
  };
  const slider=(name:keyof Appearance,title:string,min:number,max:number,suffix:string)=>
    <label className="cg-slider"><span>{title}<b>{appearance[name] as number}{suffix}</b></span>
      <input type="range" data-setting={name} min={min} max={max} value={appearance[name] as number}
        onChange={e=>set(name,Number(e.target.value))}/></label>;
  const body=()=>{
    switch(tab){
      case "General":return <>
        <section className="cg-glass cg-progress-section"><h3>Preferences backup</h3><p>Save your appearance and download preferences for a new Windows installation. Passwords, account credentials and browser cookies are not included; file paths may need updating.</p><div className="cg-bottom-actions"><button className="cg-btn" onClick={async()=>{setError("");try{const file=await savePreferences();if(file)setNotice("Preferences backup saved.")}catch(e){setError(String(e))}}}>Save backup…</button><button className="cg-btn" onClick={async()=>{setError("");try{if(await restorePreferences()){setNotice("Preferences restored. Reopen Auralis windows to apply the appearance.");location.reload()}}catch(e){setError(String(e))}}}>Restore backup…</button></div></section>
        <label className="cg-toggle"><span><strong>Start Auralis with Windows</strong><small>Launch Auralis automatically when you sign in to Windows.</small></span><input type="checkbox" disabled={!startup||busy} checked={startup?.enabled??false} onChange={e=>void changeStartup(e.target.checked,startup?.mode??"minimized")}/></label>
        <label className="cg-field">When Windows starts<select value={startup?.mode??"minimized"} disabled={!startup||busy} onChange={e=>void changeStartup(startup?.enabled??false,e.target.value)}><option value="minimized">Start minimized in the system tray</option><option value="window">Open the main window</option></select><small>Applies to Windows startup. Open Auralis normally from its shortcut whenever you want the main window.</small></label>
        <p>Browser captures wait for Download File Info so you can confirm the destination and download options.</p>
        <label className="cg-field">Copied download links<select value={appearance.clipboardMode} disabled={busy} onChange={async e=>{const mode=e.target.value;setBusy(true);setError('');try{await invoke('glass_tool',{action:'original-setting',payload:{key:'glass_clipboard_auto_download',value:mode==='auto'}});await invoke('glass_tool',{action:'original-setting',payload:{key:'clipboard_autostart',value:mode==='auto'||mode==='offer'}});set('clipboardMode',mode);setNotice('Saved.')}catch(e){setError(String(e))}finally{setBusy(false)}}}><option value="offer">Ask when a link is copied</option><option value="auto">Download supported copied links automatically</option><option value="paste">Paste when Add URL opens</option><option value="off">Do nothing</option></select></label>
        {check("only_add_to_queue","Queue silent download requests","Applies when an address is added without a confirmation dialog")}
        {check("confirm_delete","Ask before deleting","Protect items and downloaded files")}
        {check("double_click_open","Double-click opens a finished file","When off, double-click displays download details")}
        {check("show_complete","Show download complete dialog","Show a separate window when a download finishes")}
        {check("show_progress","Open a download progress window","A separate movable status window")}
      </>;
      case "Downloads":return <>
        <button className="cg-btn" onClick={()=>openWindow("tool-category","/?tool=category",680,520)}>Edit categories</button>
        <p>Choose folders and categories for downloaded files.</p>
        {(cfg?.category_dirs??[]).map(([category,path])=>
          <div className="cg-queue-row" key={category}><span><Folder size={14} style={{marginRight:9}}/>{category}</span><span className="cg-muted" title={path}>{path}</span></div>)}
        {check("only_add_to_queue","Queue download requests","Keep downloads in the main queue until started")}
        {check("confirm_delete","Confirm remove or delete","Ask before files are removed")}
        <div className="cg-settings-fallback">More options includes category folders, duplicate-download handling, and archive extraction preferences.</div>
      </>;
      case "Connection":return <>
        {adapterPicker()}
        {number("max_connections","Maximum connections per download","The selected connection count for new downloads",1,128)}
        {check("speed_limit_on","Enable global per-file speed limiter","Apply configured speed threshold")}
        {number("speed_limit_kb","Maximum speed per file (KB/s)","The default limit for each download",0,10000000)}
        {check("global_limit_on","Enable total bandwidth cap","Limit combined download traffic")}
        {number("global_limit_kb","Global cap (KB/s)","Applies across all active downloads",0,10000000)}
        <div className="cg-settings-fallback">Per-file limits are available directly in each download window's Speed Limiter tab.</div>
      </>;
      case "Browser Integration":return <>
        <h3>Auralis browser extension</h3>
        <button className="cg-btn cg-btn-primary" onClick={()=>openWindow("tool-browser-guide","/?tool=browser-guide",720,620)}>Set up browser and all media helpers…</button>
        <p>Prepare the bundled extension and register its browser connection. Browser security requires you to approve installation yourself.</p>
        <div className={`cg-integration-status ${connection?.recently_connected?"connected":"waiting"}`} role="status"><strong>{connection?.recently_connected?"✓ Browser extension connected recently":"● No recent extension connection"}</strong><span>{connection?.recently_connected?"A browser reached the Auralis helper.":connection?.previously_connected?"A browser connected before; open or reload the extension to check again.":"Open setup to install and connect the extension."}</span></div>
        <div className="cg-settings-fallback">{browser||"Checking browser helper…"}</div>
        <CrystalHelpers/>
        {check("advanced_integration","Enable advanced browser integration","Apply your browser capture rules")}
        {check("capture_opened","Capture opened URLs","Capture eligible downloads and opened links")}
        {check("proxy_from_browser","Use browser proxy","Preserve the browser's proxy, cookies and referrer context")}
        <div className="cg-settings-fallback">After installing, restart the browser if the extension does not connect. Try a real download link to confirm interception.</div>
      </>;
      case "Torrents":return <>
        <label className="cg-field">Recovery after a non-resumable download fails<select value={cfg?.torrent_recovery_mode??"off"} disabled={!cfg||busy} onChange={e=>void change("torrent_recovery_mode",e.target.value)}><option value="off">Off — search manually</option><option value="ask">Search for matching torrents, then ask me</option><option value="auto">Search and continue automatically when unambiguous</option></select><small>Search sends words from the filename to Internet Archive. Continuing uses BitTorrent peers. Matching saved pieces do not verify the unseen remainder. Automatic continuation requires one match with at least two verified pieces and no failed candidate checks; otherwise, review the results manually. The original partial is kept. Private downloads and files with an expected checksum are excluded.</small></label>
        {check("torrent_keep_sharing","Continue sharing after download","Keep uploading to other peers after the file finishes")}
        {check("torrent_dht","Use distributed hash table (DHT)","Discover BitTorrent peers")}
        {check("torrent_lsd","Discover local peers (LSD)","Use local peer discovery")}
        <div className="cg-settings-fallback">Add Torrent accepts .torrent files and magnet links.</div>
      </>;
      case "Scheduler":return <>
        <button className="cg-btn cg-btn-primary" onClick={()=>openWindow("scheduler","/?schedule=1",860,660)}>Edit schedules and completion actions</button>
        <p>Start and stop your download queues here.</p>
        {(queues??[]).map(q=><div key={q.name} className="cg-queue-row">
          <div><strong>{q.name}</strong><small>{q.ids.length} items • {q.running?"Running":"Stopped"}</small></div>
          <button className="cg-btn" disabled={busy} onClick={async()=>{
            setBusy(true);setError("");
            try{await invoke("queue_action",{name:q.name,action:q.running?"stop_queue":"start_queue"});await load()}catch(e){setError(String(e))}finally{setBusy(false)}
          }}>{q.running?"Stop queue":"Start queue"}</button>
        </div>)}
        {!queues.length&&<p>No queues reported by the engine.</p>}
      </>;
      case "Accounts":return <CrystalAccounts/>;
      case "Appearance":return <>
        <nav className="cg-appearance-tabs" aria-label="Appearance sections">{["Appearance","Indicators","Typography"].map(name=><button key={name} className={appearanceTab===name?"selected":""} onClick={()=>setAppearanceTab(name)}>{name}</button>)}</nav>
        {appearanceTab==="Appearance"&&<>
        <h3>Color themes</h3>
        <div className="cg-color-choices">{[...themes,...customThemes.map(f=>paletteForTheme(f.palette))].map(t=><button key={t.id} className={appearance.theme===t.id?"selected":""}
          onClick={()=>{const file=customThemes.find(f=>themeId(f.palette)===t.id);if(file){try{applyTheme(file)}catch(e){setError(String(e))}}else{set("theme",t.id);if(!t.neutralTint)set("tintHue",themeHue(t))}}}><i style={{background:t.neutralTint?`linear-gradient(140deg,rgb(${t.neutralTint.join(',')}),${t.secondary})`:`linear-gradient(140deg,${t.accent},${t.secondary})`}}/>{t.name}
        </button>)}</div>
        <div className="cg-wall-choice"><button className="cg-btn" onClick={()=>{setError('');void exportTheme().catch(e=>setError(`Could not export theme: ${String(e)}`))}}>Export current theme…</button><label className="cg-btn cg-material-import">Import theme…<input type="file" accept=".json,application/json" onChange={async e=>{const file=e.currentTarget.files?.[0];e.currentTarget.value='';if(!file)return;setError('');try{if(file.size>32768)throw Error('Theme file exceeds 32 KB.');const value=parseTheme(JSON.parse(await file.text()));const updated=[...customThemes.filter(t=>themeId(t.palette)!==themeId(value.palette)),value];if(updated.length>32)throw Error('A maximum of 32 custom themes is supported.');applyTheme(value);localStorage.setItem(THEMES_KEY,JSON.stringify(updated));setCustomThemes(updated);setNotice(`Imported ${value.palette.name}.`)}catch(err){setError(`Could not import theme: ${String(err)}`)}}}/></label>{appearance.theme.startsWith('user-')&&<button className="cg-btn" onClick={()=>{const updated=customThemes.filter(t=>themeId(t.palette)!==appearance.theme);localStorage.setItem(THEMES_KEY,JSON.stringify(updated));setCustomThemes(updated);set('theme','silver')}}>Remove imported theme</button>}</div>
        <div className="cg-settings-fallback">Your color theme controls the surfaces, buttons and highlights. Indicator colors remain separately adjustable.</div>
        </>}
        {appearanceTab==="Appearance"&&<><h3>Surface material</h3>
        <div className="cg-wall-choice">{[["brushed-glass","Brushed Glass"],["frosted-water-351","Frosted Layers"],["rose-pine","Rose Pine"],["window-glass","Window Glass"],["oversimplified","Oversimplified & Accentuated"],...Object.entries(extraMaterials).map(([id,m])=>[id,m.name]),...customMaterials.map(m=>[materialId(m),m.name])].map(([id,label])=><button key={id} className={`cg-btn cg-material-choice ${appearance.material===id?"cg-material-selected":""}`} aria-pressed={appearance.material===id} onClick={()=>set("material",id)}>{appearance.material===id&&<span aria-hidden="true">✓ </span>}{label}{appearance.material===id&&<span className="cg-selected-label">Selected</span>}</button>)}</div><p>Choose a surface style. Its glass color follows your selected theme; indicator colors remain separate.</p>
        <div className="cg-wall-choice"><button className="cg-btn" onClick={async()=>{setError('');try{const material=customMaterials.find(m=>materialId(m)===appearance.material)??materialPresets[appearance.material]??extraMaterials[appearance.material];const file=await invoke<string|null>('export_material_file',{contents:JSON.stringify(material,null,2)+'\n'});if(file)setNotice('Material template exported. Edit the JSON file, then import it here.')}catch(e){setError(String(e))}}}>Export editable material…</button><label className="cg-btn cg-material-import">Import material…<input type="file" accept=".json,application/json" onChange={async e=>{const file=e.currentTarget.files?.[0];e.currentTarget.value='';if(!file)return;setError('');try{if(file.size>16384)throw Error('Material file exceeds 16 KB.');const material=parseMaterial(JSON.parse(await file.text()));const updated=[...customMaterials.filter(m=>materialId(m)!==materialId(material)),material];if(updated.length>32)throw Error('A maximum of 32 custom materials is supported.');localStorage.setItem(MATERIALS_KEY,JSON.stringify(updated));setCustomMaterials(updated);set('material',materialId(material));setNotice(`Imported ${material.name}.`)}catch(err){setError(`Could not import material: ${String(err)}`)}}}/></label>{appearance.material.startsWith('custom-')&&<button className="cg-btn" onClick={()=>{const updated=customMaterials.filter(m=>materialId(m)!==appearance.material);localStorage.setItem(MATERIALS_KEY,JSON.stringify(updated));setCustomMaterials(updated);set('material','frosted-water-351')}}>Remove custom material</button>}</div>
        <small>Material files define a finish, control shape, translucency and shading. They do not contain code. The Frosted Layers template approximates its animated glass using these editable settings.</small>{slider("tintStrength","Theme tint strength",0,65,"%")}</>}
        {appearanceTab==="Indicators"&&<><h3>Indicator styles</h3><p>Choose each indicator independently. Previews update as you choose.</p><nav className="cg-indicator-tabs" aria-label="Indicator preview">{["Progress","Connections","Graph"].map(name=><button key={name} type="button" aria-pressed={indicatorTab===name} className={indicatorTab===name?"selected":""} onClick={()=>setIndicatorTab(name)}>{name}</button>)}</nav><div className="cg-indicator-cards">{([ ["Progress", "progressShape", "indicator"], ["Connections", "connectionShape", "connectionIndicator"] ] as const).map(([label,shapeKey,colorKey])=><section className="cg-indicator-card" key={label} hidden={indicatorTab!==label}><strong>{label}</strong>{label==="Progress"&&<label className="cg-field">Fill<select value={appearance.progressMaterial} onChange={e=>set("progressMaterial",e.target.value)}><option value="gradient">Color gradient</option><option value="frosted-ribbon">Approved ice ribbon</option>{liquidMaterials.map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></label>}{label==="Connections"&&<label className="cg-field">Fill<select value={appearance.connectionMaterial} onChange={e=>set("connectionMaterial",e.target.value)}><option value="gradient">Color gradient</option>{liquidMaterials.map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></label>}<label className="cg-field">Shape<select value={appearance[shapeKey]} onChange={e=>set(shapeKey,e.target.value)}>{[["rounded","Rounded"],["faceted","Faceted"],["droplet","Water droplet"],["square","Square"]].map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></label><label className="cg-field">Gradient<select value={appearance[colorKey]} onChange={e=>set(colorKey,e.target.value)}>{Object.entries(indicatorPalettes).map(([id,p])=><option key={id} value={id}>{p.label}</option>)}</select></label><div className="cg-card-preview">{label==="Progress"?<GradientBar percent={64} showLabel/>:<ConnectionMap compact downloading connections={Array.from({length:8},(_,id)=>({id,downloaded:40+id*5,speed:2,state:"Receiving"}))} segments={Array.from({length:8},(_,id)=>({start:0,cursor:40+id*5,end:100,worker:id}))}/>}</div></section>)}<section className="cg-indicator-card" hidden={indicatorTab!=="Progress"}><strong>Progress backdrop</strong><label className="cg-field">Finish<select value={appearance.trackFinish} onChange={e=>set("trackFinish",e.target.value)}><option value="default">Default</option><option value="clear">Clear glass</option><option value="frosted">Frosted</option><option value="recessed">Recessed</option></select></label><label className="cg-field">Backdrop tint<select value={appearance.trackColor} onChange={e=>set("trackColor",e.target.value)}><option value="ice">Ice</option><option value="violet">Violet</option><option value="teal">Teal</option><option value="amber">Amber</option><optgroup label="Gradient and solid palettes">{Object.entries(indicatorPalettes).map(([id,p])=><option key={id} value={`palette:${id}`}>{p.label}</option>)}</optgroup></select></label><div className="cg-card-preview"><GradientBar percent={64} showLabel/></div></section><section className="cg-indicator-card" hidden={indicatorTab!=="Connections"}><strong>Connections backdrop</strong><label className="cg-field">Finish<select value={appearance.connectionTrackFinish} onChange={e=>set("connectionTrackFinish",e.target.value)}><option value="default">Default</option><option value="clear">Clear glass</option><option value="frosted">Frosted</option><option value="recessed">Recessed</option></select></label><label className="cg-field">Backdrop tint<select value={appearance.connectionTrackColor} onChange={e=>set("connectionTrackColor",e.target.value)}><option value="ice">Ice</option><option value="violet">Violet</option><option value="teal">Teal</option><option value="amber">Amber</option><optgroup label="Gradient and solid palettes">{Object.entries(indicatorPalettes).map(([id,p])=><option key={id} value={`palette:${id}`}>{p.label}</option>)}</optgroup></select></label><div className="cg-card-preview"><ConnectionMap compact downloading connections={Array.from({length:8},(_,id)=>({id,downloaded:40+id*5,speed:2,state:"Receiving"}))} segments={Array.from({length:8},(_,id)=>({start:0,cursor:40+id*5,end:100,worker:id}))}/></div></section><section className="cg-indicator-card" hidden={indicatorTab!=="Graph"}><strong>Graph</strong><label className="cg-field">Material<select value={appearance.graphMaterial} onChange={e=>set("graphMaterial",e.target.value)}><option value="gradient">Color gradient</option>{liquidMaterials.map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></label><label className="cg-field">Shape<select value={appearance.graphShape} onChange={e=>set("graphShape",e.target.value)}><option value="area">Filled area</option><option value="line">Line</option><option value="bars">Bars</option></select></label><label className="cg-field">Gradient<select value={appearance.graphIndicator} onChange={e=>set("graphIndicator",e.target.value)}>{Object.entries(indicatorPalettes).map(([id,p])=><option key={id} value={id}>{p.label}</option>)}</select></label><div className="cg-card-preview"><SpeedGraph values={[2,4,3,7,6,10,8,11,9,12]}/></div></section></div></>}
        {appearanceTab==="Appearance"&&<>
        <p>The selected material automatically controls its translucency and Windows backdrop effect. Your color theme supplies the tint.</p>
        <h3>Independent translucent backgrounds</h3>
        {mode("main")}{mode("details")}
        </>}
        {appearanceTab==="Appearance"&&<>
        {slider("blur","Wallpaper blur",0,20," px")}
        {slider("dim","Wallpaper darkness",0,80,"%")}
        {slider("uiScale","Interface size",80,150,"%")}
        </>}
        {appearanceTab==="Typography"&&<>
        <h3>Typography and contrast</h3>
        <label className="cg-field">Font family
          <select value={appearance.fontFamily} onChange={e=>set("fontFamily",e.target.value)}>
            <option value="Segoe UI">Segoe UI / Windows</option>
            <option value="Inter">Inter</option>
            <option value="Arial">Arial</option>
            <option value="Consolas">Consolas</option>
            <option value="Trebuchet MS">Trebuchet</option><option value="Verdana">Verdana</option><option value="Georgia">Georgia</option><option value="Candara">Candara</option><option value="Century Gothic">Century Gothic</option><option value="Palatino Linotype">Palatino</option><option value="Tahoma">Tahoma</option>
          </select>
        </label>
        {slider("fontSize","Text size",12,20," px")}
        <label className="cg-toggle"><span><strong>High-contrast text</strong><small>Improve readability across materials</small></span><input type="checkbox" checked={appearance.highContrast} onChange={e=>set("highContrast",e.target.checked)}/></label>
        <p>Text contrast automatically adjusts for light/dark material. Glass panels keep a readable text backing even over bright wallpapers.</p>
        </>}
        <label className="cg-toggle"><span><strong>Show actual download popup automatically</strong><small>Open the separate floating progress window when a download starts</small></span>
          <input type="checkbox" checked={appearance.autoPopups} onChange={e=>set("autoPopups",e.target.checked)}/></label>
        <button className="cg-btn" style={{marginTop:15}} onClick={()=>{
          set("mainMode","desktop");set("detailMode","desktop");
          set("acrylic",false);set("surfaceStyle","material");set("dim",26);set("opacity",100);set("blur",6);
          set("uiScale",97);set("lightMode",false);set("fontFamily","Trebuchet MS");
          set("fontSize",14);set("highContrast",true);set("theme","ocean");set("material","rose-pine");set("tintHue",203);set("tintStrength",0);set("indicator","aurora");set("connectionIndicator","aurora");set("graphIndicator","aurora");set("progressMaterial","liquid-aero");set("connectionMaterial","liquid-aero");set("graphMaterial","gradient");set("progressShape","rounded");set("connectionShape","rounded");set("trackFinish","recessed");set("connectionTrackFinish","recessed");set("trackColor","ice");set("connectionTrackColor","ice");
        }}><RotateCcw size={15}/> Restore default appearance</button>
      </>;
      case "Advanced":return <CrystalOriginalSettings section="Advanced"/>;
    }
  };
  return <CrystalWindow target="details"><WindowTop title="Settings — Auralis Download Manager"/>
    <div className="cg-settings"><aside className="cg-settings-nav cg-glass">
      {tabs.map(t=>{const Icon=t.icon;return <button key={t.name} className={tab===t.name?"selected":""} onClick={()=>{setTab(t.name);setSettingsPanel("Main options")}}><Icon size={17}/><span>{t.name}</span></button>})}
    </aside><div className="cg-settings-body cg-glass">
      <div style={{display:"flex",justifyContent:"space-between",alignItems:"center"}}>
        <div><h2>{tab}</h2><p>Download and appearance preferences</p><p className="cg-settings-version">Current version: <strong>{appVersion||"Checking…"}</strong></p></div>
        <span className="cg-status-message">{busy?"Saving…":cfg?<><Check size={14}/> Connected</>:"Connecting"}</span>
      </div>
      {error&&<p className="cg-error">{error}</p>}
      {notice&&<p className="cg-success"><CheckCircle2 size={14}/> {notice}</p>}
      {tab!=="Appearance"&&tab!=="Accounts"&&<nav className="cg-appearance-tabs">{tab!=="Advanced"&&<button className={settingsPanel==="Main options"?"selected":""} onClick={()=>setSettingsPanel("Main options")}>Common settings</button>}<button className={settingsPanel==="More options"||(tab==="Advanced"&&settingsPanel==="Main options")?"selected":""} onClick={()=>setSettingsPanel("More options")}>All settings</button>{tab==="Advanced"&&<button className={settingsPanel==="Updates"?"selected":""} onClick={()=>setSettingsPanel("Updates")}>Updates</button>}</nav>}
      <div>{tab==="Advanced"&&settingsPanel==="Updates"?<><label className="cg-field">Update notification<select value={updatePresentation} onChange={e=>{setUpdatePresentation(e.target.value);localStorage.setItem("auralis-update-presentation",e.target.value)}}><option value="quiet">Quiet — show in Auralis only</option><option value="notify">Windows notification and Auralis corner popup</option><option value="toast">Auralis corner popup only</option><option value="dialog">Open update details immediately</option></select></label><CrystalUpstream/>{adapterPicker()}</>:tab==="Appearance"||tab==="Accounts"||settingsPanel==="Main options"?body():<CrystalOriginalSettings section={tab}/>}</div>
    </div></div>
    <footer className="cg-bottom-actions" style={{padding:"9px 18px"}}><span className="cg-muted" style={{marginRight:"auto",fontSize:"var(--min-text-size)"}}>Auralis {appVersion||"…"} • Windows x64 • Changes are saved automatically</span>
      <button className="cg-btn cg-btn-primary" onClick={()=>void import("@tauri-apps/api/window").then(m=>m.getCurrentWindow().close())}>Done</button>
    </footer>
  </CrystalWindow>;
}
