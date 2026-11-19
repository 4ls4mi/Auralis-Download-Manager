import {sculptedShapes} from "./SculptedTrack";
import { listen } from "@tauri-apps/api/event";
import CrystalAccounts from "./CrystalAccounts";
import CrystalHelpers from "./CrystalHelpers";
import CrystalUpstream from "./CrystalUpstream";
import CrystalOriginalSettings from "./CrystalOriginalSettings";
import { useEffect, useState, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Activity, Check, CheckCircle2, Download, Folder, Gauge, Globe2, Image, Network, Palette, RotateCcw, Settings, SlidersHorizontal } from "lucide-react";
import { CrystalWindow, WindowTop, GradientBar, SpeedGraph, ConnectionMap, themes, indicatorPalettes, useCrystal, openWindow } from "./CrystalShared";
import type { Appearance, BackgroundMode, Queue } from "./CrystalShared";

type EngineSettings = {
  max_connections:number;speed_limit_on:boolean;speed_limit_kb:number;global_limit_on:boolean;
  global_limit_kb:number;start_immediately:boolean;only_add_to_queue:boolean;confirm_delete:boolean;
  torrent_keep_sharing:boolean;torrent_dht:boolean;torrent_lsd:boolean;
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
  const [appearanceTab,setAppearanceTab]=useState("Theme");
  const [indicatorTab,setIndicatorTab]=useState("Progress");
  const [materialPage,setMaterialPage]=useState(0);
  const [cfg,setCfg]=useState<EngineSettings|null>(null);
  const [queues,setQueues]=useState<Queue[]>([]);
  const [busy,setBusy]=useState(false),[error,setError]=useState(""),[notice,setNotice]=useState("");
  const [browser,setBrowser]=useState("");
  const [extensionBrowser,setExtensionBrowser]=useState("edge");
  const [connection,setConnection]=useState<{recently_connected:boolean;previously_connected:boolean}|null>(null);
  const {appearance,set}=useCrystal();
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
      <strong>{target==="main"?"Main MDM window background":"Download and other popup backgrounds"}</strong>
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
        {number("max_connections","Maximum connections per download","The selected connection count for new downloads",1,128)}
        {check("speed_limit_on","Enable global per-file speed limiter","Apply configured speed threshold")}
        {number("speed_limit_kb","Maximum speed per file (KB/s)","The default limit for each download",0,10000000)}
        {check("global_limit_on","Enable total bandwidth cap","Limit combined download traffic")}
        {number("global_limit_kb","Global cap (KB/s)","Applies across all active downloads",0,10000000)}
        <div className="cg-settings-fallback">Per-file limits are available directly in each download window's Speed Limiter tab.</div>
      </>;
      case "Browser Integration":return <>
        <h3>Auralis browser extension</h3>
        <p>Prepare the bundled extension and register its browser connection. Browser security requires you to approve installation yourself.</p>
        <label className="cg-field">Browser<select value={extensionBrowser} onChange={e=>setExtensionBrowser(e.target.value)}><option value="edge">Microsoft Edge</option><option value="chromium">Chrome / Chromium</option><option value="firefox">Firefox</option></select></label>
        {extensionBrowser==="edge"&&<p>Open <strong>edge://extensions</strong>, enable Developer mode, choose <strong>Load unpacked</strong>, and select the folder opened by Auralis.</p>}
        {extensionBrowser==="chromium"&&<p>Open <strong>chrome://extensions</strong>, enable Developer mode, choose <strong>Load unpacked</strong>, and select the folder opened by Auralis.</p>}
        {extensionBrowser==="firefox"&&<p>Open <strong>about:debugging</strong>, choose This Firefox, then Load Temporary Add-on and select manifest.json in the opened folder. Firefox removes temporary add-ons when it closes; permanent installation requires a signed extension.</p>}
        <div className={`cg-integration-status ${connection?.recently_connected?"connected":"waiting"}`} role="status"><strong>{connection?.recently_connected?"✓ Browser extension connected recently":"● No recent extension connection"}</strong><span>{connection?.recently_connected?"A browser reached the native helper.":connection?.previously_connected?"A browser connected before; open or reload the extension to check again.":"Follow the steps above, then reload your browser to establish a connection."}</span></div><div className="cg-settings-fallback">{browser||"Checking for bundled native-messaging helper…"}</div>
        <button className="cg-btn cg-btn-primary" style={{marginTop:12}} disabled={busy} onClick={async()=>{setBusy(true);setError("");setNotice("");try{const folder=await invoke<string>("prepare_auralis_extension",{browser:extensionBrowser});setNotice(`Extension ready in ${folder}. Follow the browser steps above.`);setBrowser("Native helper registered. Complete installation in your browser, then check the connection status.")}catch(e){setError(String(e))}finally{setBusy(false)}}}><RotateCcw size={17}/> Prepare extension and repair connection</button>
        <div style={{height:14}}/>
        {check("advanced_integration","Enable advanced browser integration","Apply your browser capture rules")}
        {check("capture_opened","Capture opened URLs","Capture eligible downloads and opened links")}
        {check("proxy_from_browser","Use browser proxy","Preserve the browser's proxy, cookies and referrer context")}
        <div className="cg-settings-fallback">After installing, restart the browser if the extension does not connect. Try a real download link to confirm interception.</div>
      </>;
      case "Torrents":return <>
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
        <nav className="cg-appearance-tabs" aria-label="Appearance sections">{["Theme","Materials","Indicators","Backgrounds","Glass & scaling","Typography"].map(name=><button key={name} className={appearanceTab===name?"selected":""} onClick={()=>setAppearanceTab(name)}>{name}</button>)}</nav>
        {appearanceTab==="Theme"&&<>
        <h3>Crystalline ice color themes</h3>
        <div className="cg-color-choices">{themes.map(t=><button key={t.id} className={appearance.theme===t.id?"selected":""}
          onClick={()=>set("theme",t.id)}><i style={{background:`linear-gradient(140deg,${t.accent},${t.secondary})`}}/>{t.name}
        </button>)}</div>
        <h3>Solid background colors</h3>
        <div className="cg-wall-choice">
          <button className={`cg-btn ${!appearance.lightMode?"cg-btn-primary":""}`}
            onClick={()=>set("lightMode",false)}>Dark solid</button>
          <button className={`cg-btn ${appearance.lightMode?"cg-btn-primary":""}`}
            onClick={()=>set("lightMode",true)}>Light solid</button>
        </div>
        <div className="cg-settings-fallback">Glass materials keep their own appearance. Light and dark colors apply to solid backgrounds. Download indicators keep their independent color settings.</div>
        </>}
        {appearanceTab==="Materials"&&<><h3>Glass material</h3>
        <div className="cg-wall-choice">{[["ice-edge","Ice Edge"],["smoked-crystal","Smoked Crystal"],["frosted-layers","Frosted Layers"],["aero-gloss","Aero Gloss"],["prismatic-glass","Prismatic Glass"],["liquid-glass","Liquid Glass"],["obsidian-glass","Obsidian Glass"],["diamond-facet","Diamond Facet"],["holographic-film","Holographic Film"],["pearl-mist","Pearl Mist"],["aurora-veil","Aurora Veil"],["brushed-glass","Brushed Glass"],["water-bubble","Water Bubble Glass"],["frosted-water-351","Frosted Layers 3.5.1"],["rose-pine","Rose Pine"],["window-glass","Window Glass"],["oversimplified","Oversimplified & Accentuated"],["tinted-glass","Tinted Glass"],["frosty-glass","Frosty Glass"],["raycast","Raycast"]].slice(materialPage*5,materialPage*5+5).map(([id,label])=><button key={id} className={`cg-btn ${appearance.material===id?"cg-btn-primary":""}`} onClick={()=>set("material",id)}>{label}</button>)}</div><div className="cg-pagination"><button disabled={materialPage===0} onClick={()=>setMaterialPage(n=>n-1)}>Previous</button><span>{materialPage+1} / 4</span><button disabled={materialPage===3} onClick={()=>setMaterialPage(n=>n+1)}>Next</button></div><p>Choose a surface style for light and dark windows.</p>{slider("tintHue","Glass tint color",0,360,"°")}{slider("tintStrength","Glass tint strength",0,65,"%")}</>}
        {appearanceTab==="Indicators"&&<><h3>Indicator styles</h3><p>Choose each indicator independently. Previews update as you choose.</p><nav className="cg-indicator-tabs" aria-label="Indicator preview">{["Progress","Connections","Progress backdrop","Connections backdrop","Graph"].map(name=><button key={name} type="button" aria-pressed={indicatorTab===name} className={indicatorTab===name?"selected":""} onClick={()=>setIndicatorTab(name)}>{name}</button>)}</nav><div className="cg-indicator-cards">{([ ["Progress", "progressShape", "indicator"], ["Connections", "connectionShape", "connectionIndicator"] ] as const).map(([label,shapeKey,colorKey])=><section className="cg-indicator-card" key={label} hidden={indicatorTab!==label}><strong>{label}</strong>{label==="Progress"&&appearance.progressShape==="rounded"&&<label className="cg-field">Fill<select value={appearance.progressMaterial} onChange={e=>set("progressMaterial",e.target.value)}><option value="gradient">Color gradient</option><option value="frosted-ribbon">Approved ice ribbon (rounded)</option></select></label>}<label className="cg-field">Shape<select value={appearance[shapeKey]} onChange={e=>set(shapeKey,e.target.value)}>{[["rounded","Rounded"],["faceted","Faceted"],["droplet","Water droplet"],["square","Square"],...Object.entries(sculptedShapes).map(([id,shape])=>[id,shape.label])].map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></label><label className="cg-field">Gradient<select value={appearance[colorKey]} onChange={e=>set(colorKey,e.target.value)}>{Object.entries(indicatorPalettes).map(([id,p])=><option key={id} value={id}>{p.label}</option>)}</select></label>{label==="Progress"&&appearance.progressShape!=="rounded"&&<small>Shaped glass uses the selected indicator colors.</small>}<div className="cg-card-preview">{label==="Progress"?<GradientBar percent={64} showLabel/>:<ConnectionMap compact downloading connections={Array.from({length:8},(_,id)=>({id,downloaded:40+id*5,speed:2,state:"Receiving"}))} segments={Array.from({length:8},(_,id)=>({start:0,cursor:40+id*5,end:100,worker:id}))}/>}</div></section>)}<section className="cg-indicator-card" hidden={indicatorTab!=="Progress backdrop"}><strong>Progress backdrop</strong><label className="cg-field">Finish<select value={appearance.trackFinish} onChange={e=>set("trackFinish",e.target.value)}><option value="default">Default</option><option value="clear">Clear glass</option><option value="frosted">Frosted</option><option value="recessed">Recessed</option></select></label><label className="cg-field">Backdrop tint<select value={appearance.trackColor} onChange={e=>set("trackColor",e.target.value)}><option value="ice">Ice</option><option value="violet">Violet</option><option value="teal">Teal</option><option value="amber">Amber</option><optgroup label="Gradient and solid palettes">{Object.entries(indicatorPalettes).map(([id,p])=><option key={id} value={`palette:${id}`}>{p.label}</option>)}</optgroup></select></label><div className="cg-card-preview"><GradientBar percent={64} showLabel/></div></section><section className="cg-indicator-card" hidden={indicatorTab!=="Connections backdrop"}><strong>Connections backdrop</strong><label className="cg-field">Finish<select value={appearance.connectionTrackFinish} onChange={e=>set("connectionTrackFinish",e.target.value)}><option value="default">Default</option><option value="clear">Clear glass</option><option value="frosted">Frosted</option><option value="recessed">Recessed</option></select></label><label className="cg-field">Backdrop tint<select value={appearance.connectionTrackColor} onChange={e=>set("connectionTrackColor",e.target.value)}><option value="ice">Ice</option><option value="violet">Violet</option><option value="teal">Teal</option><option value="amber">Amber</option><optgroup label="Gradient and solid palettes">{Object.entries(indicatorPalettes).map(([id,p])=><option key={id} value={`palette:${id}`}>{p.label}</option>)}</optgroup></select></label><div className="cg-card-preview"><ConnectionMap compact downloading connections={Array.from({length:8},(_,id)=>({id,downloaded:40+id*5,speed:2,state:"Receiving"}))} segments={Array.from({length:8},(_,id)=>({start:0,cursor:40+id*5,end:100,worker:id}))}/></div></section><section className="cg-indicator-card" hidden={indicatorTab!=="Graph"}><strong>Graph</strong><label className="cg-field">Shape<select value={appearance.graphShape} onChange={e=>set("graphShape",e.target.value)}><option value="area">Filled area</option><option value="line">Line</option><option value="bars">Bars</option></select></label><label className="cg-field">Gradient<select value={appearance.graphIndicator} onChange={e=>set("graphIndicator",e.target.value)}>{Object.entries(indicatorPalettes).map(([id,p])=><option key={id} value={id}>{p.label}</option>)}</select></label><div className="cg-card-preview"><SpeedGraph values={[2,4,3,7,6,10,8,11,9,12]}/></div></section></div></>}
        {appearanceTab==="Backgrounds"&&<>
        <h3>Independent translucent backgrounds</h3>
        {mode("main")}{mode("details")}
        </>}
        {appearanceTab==="Glass & scaling"&&<>
        {slider("opacity","Crystal glass opacity",45,94,"%")}
        {slider("blur","Wallpaper blur",0,20," px")}
        {slider("dim","Wallpaper darkness",0,80,"%")}
        {slider("uiScale","Interface size",80,150,"%")}
        <label className="cg-toggle"><span><strong>Windows backdrop blur</strong><small>Use native blur behind see-through windows when supported</small></span><input type="checkbox" checked={appearance.acrylic} onChange={e=>set("acrylic",e.target.checked)}/></label>
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
          set("acrylic",false);set("dim",26);set("opacity",77);set("blur",3);
          set("uiScale",100);set("lightMode",false);set("fontFamily","Segoe UI");
          set("fontSize",14);set("highContrast",true);set("theme","plexo");set("material","ice-edge");set("tintHue",265);set("tintStrength",22);set("indicator","blue-purple");
        }}><RotateCcw size={15}/> Restore default Glass appearance</button>
      </>;
      case "Advanced":return <>
        <CrystalHelpers/>
      </>;
    }
  };
  return <CrystalWindow target="details"><WindowTop title="Settings — Auralis Download Manager"/>
    <div className="cg-settings"><aside className="cg-settings-nav cg-glass">
      {tabs.map(t=>{const Icon=t.icon;return <button key={t.name} className={tab===t.name?"selected":""} onClick={()=>{setTab(t.name);setSettingsPanel("Main options")}}><Icon size={17}/><span>{t.name}</span></button>})}
    </aside><div className="cg-settings-body cg-glass">
      <div style={{display:"flex",justifyContent:"space-between",alignItems:"center"}}>
        <div><h2>{tab}</h2><p>Download and appearance preferences</p></div>
        <span className="cg-status-message">{busy?"Saving…":cfg?<><Check size={14}/> Connected</>:"Connecting"}</span>
      </div>
      {error&&<p className="cg-error">{error}</p>}
      {notice&&<p className="cg-success"><CheckCircle2 size={14}/> {notice}</p>}
      {tab!=="Appearance"&&tab!=="Accounts"&&<nav className="cg-appearance-tabs"><button className={settingsPanel==="Main options"?"selected":""} onClick={()=>setSettingsPanel("Main options")}>Common settings</button><button className={settingsPanel==="More options"?"selected":""} onClick={()=>setSettingsPanel("More options")}>All original settings</button>{tab==="Advanced"&&<button className={settingsPanel==="Updates"?"selected":""} onClick={()=>setSettingsPanel("Updates")}>Updates</button>}</nav>}
      <div>{tab==="Advanced"&&settingsPanel==="Updates"?<><CrystalUpstream/>{cfg&&<label className="cg-field">Preferred network adapter<input defaultValue={cfg.net_adapter} key={cfg.net_adapter} onBlur={e=>{if(e.target.value!==cfg.net_adapter)void change("net_adapter",e.target.value)}}/></label>}</>:tab==="Appearance"||tab==="Accounts"||settingsPanel==="Main options"?body():<CrystalOriginalSettings section={tab}/>}</div>
    </div></div>
    <footer className="cg-bottom-actions" style={{padding:"9px 18px"}}><span className="cg-muted" style={{marginRight:"auto",fontSize:"var(--min-text-size)"}}>Windows x64 • Changes are saved automatically</span>
      <button className="cg-btn cg-btn-primary" onClick={()=>void import("@tauri-apps/api/window").then(m=>m.getCurrentWindow().close())}>Done</button>
    </footer>
  </CrystalWindow>;
}
