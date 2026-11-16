import { useEffect, useState, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Activity, Check, CheckCircle2, Download, Folder, Gauge, Globe2, Image, Network, Palette, RotateCcw, Settings, Shield, SlidersHorizontal } from "lucide-react";
import { CrystalWindow, WindowTop, themes, useCrystal } from "./CrystalShared";
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
type Tab="General"|"Downloads"|"Connection"|"Browser Integration"|"Torrents"|"Scheduler"|"Appearance"|"Advanced";
const tabs:{name:Tab;icon:typeof Settings}[]=[
  {name:"General",icon:Settings},{name:"Downloads",icon:Download},
  {name:"Connection",icon:Network},{name:"Browser Integration",icon:Globe2},
  {name:"Torrents",icon:Activity},{name:"Scheduler",icon:Gauge},
  {name:"Appearance",icon:Palette},{name:"Advanced",icon:SlidersHorizontal}
];
export default function CrystalSettings(){
  const initial=new URLSearchParams(location.search).get("tab") as Tab|null;
  const [tab,setTab]=useState<Tab>(tabs.some(t=>t.name===initial)?initial!:"General");
  const [cfg,setCfg]=useState<EngineSettings|null>(null);
  const [queues,setQueues]=useState<Queue[]>([]);
  const [busy,setBusy]=useState(false),[error,setError]=useState(""),[notice,setNotice]=useState("");
  const [browser,setBrowser]=useState("");
  const {appearance,set}=useCrystal();
  const load=useCallback(async()=>{
    try{
      const [settings,data]=await Promise.all([
        invoke<EngineSettings>("glass_settings"),
        invoke<{queues:Queue[]}>("dashboard_snapshot")
      ]);
      setCfg(settings);setQueues(data.queues??[]);
    }catch(e){setError("The headless download engine isn't available: "+String(e))}
  },[]);
  useEffect(()=>{void load();void invoke<string>("browser_integration",{repair:false}).then(setBrowser).catch(e=>setBrowser(String(e)))},[load]);
  const change=async(key:EngineKey,value:boolean|number|string)=>{
    setBusy(true);setError("");setNotice("");
    try{
      await invoke("update_glass_setting",{key,value:String(value)});
      const result=await invoke<EngineSettings>("glass_settings");
      setCfg(result);setNotice("Saved to the active Rust downloader.");
    }catch(e){setError(String(e))}finally{setBusy(false)}
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
          {m==="desktop"?"See-through desktop":m==="wallpaper"?"Custom wallpaper":"Dark solid"}
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
      <input type="range" min={min} max={max} value={appearance[name] as number}
        onChange={e=>set(name,Number(e.target.value))}/></label>;
  const body=()=>{
    switch(tab){
      case "General":return <>
        {check("start_immediately","Start downloads immediately","Use MDM's original download behavior")}
        {check("only_add_to_queue","Add new downloads to queue","Use queue instead of immediate start")}
        {check("confirm_delete","Ask before deleting","Protect items and downloaded files")}
        {check("double_click_open","Double-click opens a finished file","When off, double-click displays download details")}
        {check("show_complete","Show download complete dialog","Restore original completion notifications")}
        {check("show_progress","Open a download progress window","The Plexo-inspired floating status window")}
      </>;
      case "Downloads":return <>
        <p>MDM's original directories are preserved and the Rust backend continues saving downloads there.</p>
        {(cfg?.category_dirs??[]).map(([category,path])=>
          <div className="cg-queue-row" key={category}><span><Folder size={14} style={{marginRight:9}}/>{category}</span><span className="cg-muted" title={path}>{path}</span></div>)}
        {check("only_add_to_queue","Queue download requests","Keep downloads in the main queue until started")}
        {check("confirm_delete","Confirm remove or delete","Ask before files are removed")}
        <div className="cg-settings-fallback">Advanced original options such as category folder editing, file-type rules and duplicate-download rules remain stored in the original data. Their Glass editing controls are not migrated yet.</div>
      </>;
      case "Connection":return <>
        {number("max_connections","Maximum connections per download","Rust MDM's real multi-segment connection count",1,128)}
        {check("speed_limit_on","Enable global per-file speed limiter","Apply configured speed threshold")}
        {number("speed_limit_kb","Maximum speed per file (KB/s)","Original MDM's default speed limiter",0,10000000)}
        {check("global_limit_on","Enable total bandwidth cap","Limit combined download traffic")}
        {number("global_limit_kb","Global cap (KB/s)","Applies across all active downloads",0,10000000)}
        <div className="cg-settings-fallback">Per-file limits are available directly in each download window's Speed Limiter tab.</div>
      </>;
      case "Browser Integration":return <>
        <h3>Original MDM browser extension</h3>
        <p>The original Chrome / Edge / Firefox native messaging protocol is used—no new browser extension is required.</p>
        <div className="cg-settings-fallback">{browser||"Checking for bundled native-messaging helper…"}</div>
        <button className="cg-btn cg-btn-primary" style={{marginTop:12}} disabled={busy}
          onClick={async()=>{setBusy(true);setError("");try{const result=await invoke<string>("browser_integration",{repair:true});setBrowser(result);setNotice("Registered with Windows. Restart your browser to reconnect the extension.")}catch(e){setError(String(e))}finally{setBusy(false)}}}>
          <RotateCcw size={17}/> Reconnect / Repair browser extension
        </button>
        <div style={{height:14}}/>
        {check("advanced_integration","Enable advanced browser integration","Use the original native-messaging download capture rules")}
        {check("capture_opened","Capture opened URLs","Capture eligible downloads and opened links")}
        {check("proxy_from_browser","Use browser proxy","Preserve the browser's proxy, cookies and referrer context")}
        <div className="cg-settings-fallback">Restart the browser after registration. Browser extension capture must be tested with a real download link; registration alone does not prove interception works.</div>
      </>;
      case "Torrents":return <>
        {check("torrent_keep_sharing","Continue sharing after download","Original torrent seeding behavior")}
        {check("torrent_dht","Use distributed hash table (DHT)","Discover BitTorrent peers")}
        {check("torrent_lsd","Discover local peers (LSD)","Use local peer discovery")}
        <div className="cg-settings-fallback">Add Torrent in the main toolbar accepts .torrent files and magnet links via the Rust torrent engine.</div>
      </>;
      case "Scheduler":return <>
        <p>Queues below are the real queues supplied by the Rust download scheduler.</p>
        {(queues??[]).map(q=><div key={q.name} className="cg-queue-row">
          <div><strong>{q.name}</strong><small>{q.ids.length} items • {q.running?"Running":"Stopped"}</small></div>
          <button className="cg-btn" disabled={busy} onClick={async()=>{
            setBusy(true);setError("");
            try{await invoke("queue_action",{name:q.name,action:q.running?"stop_queue":"start_queue"});await load()}catch(e){setError(String(e))}finally{setBusy(false)}
          }}>{q.running?"Stop queue":"Start queue"}</button>
        </div>)}
        {!queues.length&&<p>No queues reported by the engine.</p>}
      </>;
      case "Appearance":return <>
        <h3>Crystalline ice color themes</h3>
        <div className="cg-color-choices">{themes.map(t=><button key={t.id} className={appearance.theme===t.id?"selected":""}
          onClick={()=>set("theme",t.id)}><i style={{background:`linear-gradient(140deg,${t.accent},${t.secondary})`}}/>{t.name}
        </button>)}</div>
        <h3>Independent translucent backgrounds</h3>
        {mode("main")}{mode("details")}
        {slider("opacity","Crystal glass opacity",45,94,"%")}
        {slider("blur","Wallpaper blur",0,20," px")}
        {slider("dim","Wallpaper darkness",0,80,"%")}
        {slider("uiScale","Interface size",80,150,"%")}
        <label className="cg-toggle"><span><strong>Native Windows Acrylic</strong><small>Blur the desktop behind see-through windows when supported</small></span>
          <input type="checkbox" checked={appearance.acrylic} onChange={e=>set("acrylic",e.target.checked)}/></label>
        <label className="cg-toggle"><span><strong>Show actual download popup automatically</strong><small>Open the separate floating progress window when a download starts</small></span>
          <input type="checkbox" checked={appearance.autoPopups} onChange={e=>set("autoPopups",e.target.checked)}/></label>
      </>;
      case "Advanced":return <>
        <h3>Original MDM configuration</h3>
        <p>Original proxy settings, site credentials, file-type capture rules and accounts are preserved in the MDM data store. Full editing support for these sections still requires backend APIs.</p>
        <div className="cg-settings-fallback"><Shield size={18}/> Native Glass uses authenticated loopback IPC; the backend does not expose its local token to React. The original MDM download engine and settings database remain intact.</div>
        {cfg&&<label className="cg-field" style={{marginTop:18}}>Preferred network adapter<input defaultValue={cfg.net_adapter} key={cfg.net_adapter}
          onBlur={e=>{if(e.target.value!==cfg.net_adapter)void change("net_adapter",e.target.value)}}/></label>}
      </>;
    }
  };
  return <CrystalWindow target="details"><WindowTop title="Settings — Mister Hybrid Glass"/>
    <div className="cg-settings"><aside className="cg-settings-nav cg-glass">
      {tabs.map(t=>{const Icon=t.icon;return <button key={t.name} className={tab===t.name?"selected":""} onClick={()=>setTab(t.name)}><Icon size={17}/><span>{t.name}</span></button>})}
    </aside><div className="cg-settings-body cg-glass">
      <div style={{display:"flex",justifyContent:"space-between",alignItems:"center"}}>
        <div><h2>{tab}</h2><p>Unified Rust download manager and Glass appearance options</p></div>
        <span className="cg-status-message">{busy?"Saving…":cfg?<><Check size={14}/> Connected</>:"Connecting"}</span>
      </div>
      {error&&<p className="cg-error">{error}</p>}
      {notice&&<p className="cg-success"><CheckCircle2 size={14}/> {notice}</p>}
      <div>{body()}</div>
    </div></div>
    <footer className="cg-bottom-actions" style={{padding:"9px 18px"}}><span className="cg-muted" style={{marginRight:"auto",fontSize:10}}>Windows x64 • Changes to engine settings are saved by MDM</span>
      <button className="cg-btn cg-btn-primary" onClick={()=>void import("@tauri-apps/api/window").then(m=>m.getCurrentWindow().close())}>Done</button>
    </footer>
  </CrystalWindow>;
}
