import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { CSSProperties, ReactNode } from "react";
import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import {
  Activity, AlertCircle, Archive, BarChart3, Check, CheckCircle2, Clock3,
  Download, ExternalLink, File, Film, Folder, FolderOpen, HardDrive, Image,
  Link2, Maximize2, Minus, Music, Palette, Pause, Play, Plus, Search, Settings,
  Sparkles, Trash2, Video, X
} from "lucide-react";

type State = "Queued" | "Downloading" | "Stopped" | "Complete" | "Error";
type DownloadFile = { id: number; file: string; url: string; path: string; status: State;
  size: number | null; downloaded: number; speed: number; added: string | null; category: string; error?: string | null };
type Dashboard = { downloads: DownloadFile[]; speed: number;
  queues: {name:string; running:boolean; ids:number[]}[]; categories:{name:string;key:string}[]; free?:number|null };
type Theme = { id:string; name:string; color:string; rgb:string; secondary:string };
const themes:Theme[] = [
  {id:"plexo",name:"Plexo Teal",color:"#05e6d2",rgb:"5,230,210",secondary:"#4d9fed"},
  {id:"aurora",name:"Aurora Blue",color:"#4d9fed",rgb:"77,159,237",secondary:"#50d3ff"},
  {id:"amethyst",name:"Amethyst",color:"#ac83ff",rgb:"172,131,255",secondary:"#6186ff"},
  {id:"sunset",name:"Sunset",color:"#ffb357",rgb:"255,179,87",secondary:"#ff768e"},
  {id:"emerald",name:"Emerald",color:"#40e9a7",rgb:"64,233,167",secondary:"#7cf2d3"},
  {id:"crimson",name:"Crimson",color:"#ff6388",rgb:"255,99,136",secondary:"#ffb058"},
  {id:"ocean",name:"Ocean",color:"#4ed4fd",rgb:"78,212,253",secondary:"#657fff"},
  {id:"graphite",name:"Graphite",color:"#b9cde2",rgb:"185,205,226",secondary:"#8397b1"}
];
const blank:Dashboard = {downloads:[],speed:0,queues:[],categories:[]};
const store = (key:string) => "mh-glass-" + key;
const getSetting = (key:string,fallback:string) => localStorage.getItem(store(key)) ?? fallback;
const clamp = (n:number) => Math.max(0,Math.min(100,n));
const pct = (d:DownloadFile) => d.size && d.size>0 ? clamp(100*d.downloaded/d.size) : d.status==="Complete" ? 100 : 0;
const human = (v:number|null|undefined) => {
  if (v===null || v===undefined || !Number.isFinite(v)) return "Unknown";
  const n = v<1024?0:Math.min(4,Math.floor(Math.log(v)/Math.log(1024)));
  return (v/Math.pow(1024,n)).toFixed(n===0?0:1)+" "+["B","KB","MB","GB","TB"][n];
};
const speed = (n:number) => human(n)+"/s";
const statusLabel = (s:State) => ({Queued:"Queued",Downloading:"Downloading",Stopped:"Paused",Complete:"Completed",Error:"Failed"})[s];
const eta = (d:DownloadFile) => {
  if(d.status!=="Downloading" || !d.size || d.speed<=0) return "—";
  const s=Math.ceil(Math.max(0,d.size-d.downloaded)/d.speed);
  return s<60?s+"s":s<3600?Math.floor(s/60)+"m":Math.floor(s/3600)+"h "+Math.floor(s%3600/60)+"m";
};
function Glass({children,className=""}:{children:ReactNode;className?:string}){return <section className={"glass "+className}>{children}</section>}
function Brand(){return <div className="brand"><div className="brand-mark">M</div><div><strong>Mister Hybrid</strong><small>Download Manager <span>•</span> Glass Edition</small></div></div>}
function WindowButtons(){return <div className="window-buttons"><button title="Minimize" onClick={()=>void getCurrentWindow().minimize()}><Minus size={17}/></button><button title="Maximize" onClick={()=>void getCurrentWindow().toggleMaximize()}><Maximize2 size={15}/></button><button className="close-button" title="Close" onClick={()=>void getCurrentWindow().close()}><X size={19}/></button></div>}
function Badge({value}:{value:State}){return <span className={"state state-"+value.toLowerCase()}>{value==="Downloading"?<span className="live-dot"/>:value==="Complete"?<CheckCircle2 size={14}/>:value==="Stopped"?<Pause size={14}/>:value==="Error"?<AlertCircle size={14}/>:<Clock3 size={14}/>} {statusLabel(value)}</span>}
function MiniBars({percent}:{percent:number}){return <div className="mini-bars">{Array.from({length:16},(_,i)=><i key={i} className={i/16*100<percent?"filled":""} style={{"--index":i} as CSSProperties}/>)}</div>}
function ColorBlocks({percent}:{percent:number}){return <div className="color-blocks" aria-label={"Decorative color-flow progress "+Math.round(percent)+" percent"}>{Array.from({length:168},(_,i)=><i key={i} className={i/168*100<percent?"filled":""} style={{"--hue":170+i/168*115,"--i":i} as CSSProperties}/>)}</div>}
function Graph({values,small=false}:{values:number[];small?:boolean}){
  const v=values.length>1?values:[0,0], max=Math.max(1,...v)*1.2;
  const points=v.map((n,i)=>(i/(v.length-1)*100).toFixed(1)+","+(55-n/max*43).toFixed(1)).join(" ");
  return <svg className={"graph "+(small?"graph-small":"")} viewBox="0 0 100 60" preserveAspectRatio="none" aria-label="Real transfer speed history"><defs><linearGradient id="graphshade" x1="0" x2="0" y1="0" y2="1"><stop stopColor="var(--accent)" stopOpacity=".28"/><stop offset="1" stopColor="var(--accent)" stopOpacity="0"/></linearGradient></defs>{[18,37,55].map(y=><line key={y} x1="0" y1={y} x2="100" y2={y} stroke="#c9edff" strokeOpacity=".09" strokeWidth=".35"/>)}<polygon points={"0,60 "+points+" 100,60"} fill="url(#graphshade)"/><polyline points={points} fill="none" stroke="var(--accent)" strokeWidth="1.6" vectorEffect="non-scaling-stroke" strokeLinejoin="round"/></svg>
}
function IconFor({file}:{file:string}){const ext=file.split(".").pop()?.toLowerCase()??"";const Icon=["mp4","mkv","webm","mov","avi"].includes(ext)?Film:["7z","zip","rar","iso","nsp"].includes(ext)?Archive:["flac","mp3","wav"].includes(ext)?Music:["jpg","png","webp"].includes(ext)?Image:File;return <div className="file-icon"><Icon size={23}/></div>}
export default function App(){
  const detailId=Number(new URLSearchParams(location.search).get("detail"))||null;
  const [data,setData]=useState<Dashboard>(blank),[online,setOnline]=useState(false),[notice,setNotice]=useState("Connecting to Rust download engine…");
  const [chosen,setChosen]=useState<number|null>(detailId),[filter,setFilter]=useState("All Downloads"),[search,setSearch]=useState("");
  const [tab,setTab]=useState("General"),[settingTab,setSettingTab]=useState("Themes"),[settings,setSettings]=useState(false),[add,setAdd]=useState(false);
  const [input,setInput]=useState(""),[error,setError]=useState(""),[busy,setBusy]=useState(false);
  const [theme,setTheme]=useState(getSetting("theme","plexo")),[wallMain,setWallMain]=useState(getSetting("wall-main","")),[wallDetail,setWallDetail]=useState(getSetting("wall-detail",""));
  const [dim,setDim]=useState(Number(getSetting("dim","30"))),[blur,setBlur]=useState(Number(getSetting("blur","2"))),[opacity,setOpacity]=useState(Number(getSetting("opacity","55")));
  const [isBright,setBright]=useState(false),[history,setHistory]=useState<number[]>([]),[fileHistory,setFileHistory]=useState<Record<string,number[]>>({});
  const working=useRef(false),picked=themes.find(x=>x.id===theme)??themes[0],wall=detailId?(wallDetail||wallMain):wallMain;
  const url=wall?convertFileSrc(wall):"/alpine.svg",isVideo=/\.(mp4|webm|mov|m4v)$/i.test(wall);
  useEffect(()=>{document.documentElement.style.setProperty("--accent",picked.color);document.documentElement.style.setProperty("--accent-rgb",picked.rgb);document.documentElement.style.setProperty("--accent-secondary",picked.secondary);localStorage.setItem(store("theme"),theme)},[theme,picked]);
  useEffect(()=>{for(const [key,val] of [["wall-main",wallMain],["wall-detail",wallDetail],["dim",String(dim)],["blur",String(blur)],["opacity",String(opacity)]])localStorage.setItem(store(key),val)},[wallMain,wallDetail,dim,blur,opacity]);
  useEffect(()=>{
    if(isVideo){setBright(false);return}
    let active=true;const img=new window.Image();img.crossOrigin="anonymous";
    img.onload=()=>{if(!active)return;try{const canvas=document.createElement("canvas");canvas.width=24;canvas.height=24;const ctx=canvas.getContext("2d");if(!ctx)return;ctx.drawImage(img,0,0,24,24);const pix=ctx.getImageData(0,0,24,24).data;let l=0;for(let i=0;i<pix.length;i+=4)l+=(pix[i]*.2126+pix[i+1]*.7152+pix[i+2]*.0722)/255;setBright(l/(pix.length/4)>.56)}catch{setBright(false)}};
    img.src=url;return()=>{active=false};
  },[url,isVideo]);
  const refresh=useCallback(async()=>{
    if(working.current)return;working.current=true;
    try{const next=await invoke<Dashboard>("dashboard_snapshot");setData(next);setOnline(true);setNotice("Connected • Live Rust download data");setHistory(p=>[...p.slice(-59),next.speed]);
      setFileHistory(p=>{const n={...p};for(const d of next.downloads)n[String(d.id)]=[...(p[String(d.id)]??[]).slice(-59),d.speed];return n})}
    catch(e){setOnline(false);setNotice(String(e))}
    finally{working.current=false}
  },[]);
  useEffect(()=>{let alive=true;void invoke("boot_engine").then(()=>{if(alive)void refresh()}).catch(e=>{if(alive){setOnline(false);setNotice(String(e))}});
    const interval=window.setInterval(()=>{if(alive)void refresh()},1500);return()=>{alive=false;window.clearInterval(interval)}},[refresh]);
  const counts=useMemo(()=>({all:data.downloads.length,active:data.downloads.filter(d=>d.status==="Downloading").length,paused:data.downloads.filter(d=>d.status==="Stopped").length,completed:data.downloads.filter(d=>d.status==="Complete").length,queued:data.downloads.filter(d=>d.status==="Queued").length}),[data]);
  const filtered=data.downloads.filter(d=>(filter==="All Downloads"||d.status===filter||(filter==="Paused"&&d.status==="Stopped")||(filter==="Completed"&&d.status==="Complete")||(filter.startsWith("category:")&&d.category===filter.slice(9)))&&((d.file+" "+d.url).toLowerCase().includes(search.toLowerCase())));
  const item=data.downloads.find(x=>x.id===(detailId??chosen))??(detailId?undefined:filtered[0]);
  const take=async(action:"pause"|"start"|"remove")=>{if(!item)return;setBusy(true);setError("");
    try{const result=await invoke<{done:number[];skipped:{id:number;why:string}[]}>("download_action",{action,ids:[item.id]});if(result.skipped.length)setError(result.skipped.map(x=>x.why).join(", "));await refresh()}catch(e){setError(String(e))}finally{setBusy(false)}};
  const addLink=async()=>{if(!input.trim())return;setBusy(true);setError("");try{await invoke("add_download",{url:input.trim(),later:false});setAdd(false);setInput("");await refresh()}catch(e){setError(String(e))}finally{setBusy(false)}};
  const pickWall=async(target:"main"|"details")=>{try{const path=await invoke<string|null>("select_wallpaper",{target});if(path){if(target==="main")setWallMain(path);else setWallDetail(path)}}catch(e){setError(String(e))}};
  const popout=(id:number)=>{const win=new WebviewWindow("download-"+id,{url:"/?detail="+id,title:"Mister Hybrid • Download",width:720,height:790,minWidth:520,minHeight:560,center:true,decorations:false});void win.once("tauri://error",e=>setError(String(e.payload)))};
  const rootStyle={"--panel-opacity":String(Math.max(.28,Math.min(.9,opacity/100+(isBright?.12:0)))),"--wall-blur":blur+"px"} as CSSProperties;
  const wallNode=<div className="wallpaper-root">{isVideo?<video autoPlay muted loop playsInline src={url}/>:<div className="wallpaper-image" style={{backgroundImage:'url("'+url+'")'}}/>}<div className="wallpaper-mask" style={{background:"rgba(5,10,18,"+(dim/100)+")"}}/></div>;
  const detailNode=<Glass className={"detail-panel "+(detailId?"full-detail":"")}>
    <div className="detail-heading"><div className="detail-identity"><div className="detail-image">{item?<IconFor file={item.file}/>:<Download size={28}/>}</div><div><small>DOWNLOAD INSPECTOR</small><h2 title={item?.file}>{item?.file??"Select a download"}</h2><p>{item?human(item.downloaded)+" / "+human(item.size):"Actual transfer details"}</p></div></div>{!detailId&&item&&<button className="flat-icon" title="Open separate window" onClick={()=>popout(item.id)}><ExternalLink size={17}/></button>}</div>
    <div className="tab-row">{["General","Chunks","Peers","Files"].map(s=><button key={s} onClick={()=>setTab(s)} className={tab===s?"current":""}>{s}</button>)}</div>
    {item?<>
      <div className="detail-progress"><div><strong>{pct(item).toFixed(0)}%</strong><Badge value={item.status}/></div><div className="progress-track"><i style={{width:pct(item)+"%"}}/></div><div className="detail-numbers"><span>{human(item.downloaded)} / {human(item.size)}</span><span>{speed(item.speed)}</span></div></div>
      <div className="quick-stats"><div><Download size={16}/><small>Download speed</small><strong>{speed(item.speed)}</strong></div><div><Activity size={16}/><small>Recent speed</small><strong>{speed(item.speed)}</strong></div><div><Clock3 size={16}/><small>Time left</small><strong>{eta(item)}</strong></div><div><HardDrive size={16}/><small>File size</small><strong>{human(item.size)}</strong></div></div>
      {(tab==="General"||tab==="Chunks")&&<><div className="detail-section"><div className="section-title"><strong>Color-flow visualization</strong><small>{pct(item).toFixed(0)}% filled • decorative gradient</small></div><ColorBlocks percent={pct(item)}/><div className="chunk-legend"><span><i/> Teal</span><span><i/> Blue</span><span><i/> Violet</span><span>Gradual color transition, not network adapters</span></div></div><div className="detail-section"><div className="section-title"><strong>Live transfer speed</strong><b>{speed(item.speed)}</b></div><Graph values={fileHistory[String(item.id)]??[]}/></div></>}
      {(tab==="General"||tab==="Files")&&<div className="detail-section facts"><strong>Download details</strong><dl><dt>URL</dt><dd title={item.url}>{item.url}</dd><dt>Save path</dt><dd title={item.path}>{item.path}</dd><dt>Downloaded</dt><dd>{human(item.downloaded)} ({pct(item).toFixed(1)}%)</dd><dt>Status</dt><dd>{statusLabel(item.status)}</dd></dl></div>}
      {tab==="Peers"&&<div className="placeholder-panel"><Activity size={29}/><strong>Connection-level data isn't exposed yet</strong><p>This first integration displays real totals. We won't invent peer or network-adapter statistics.</p></div>}
      <div className="detail-buttons">{error&&<div className="error-message">{error}</div>}{item.status!=="Complete"&&<button className="primary-button" disabled={busy||!online} onClick={()=>void take(item.status==="Downloading"?"pause":"start")}>{item.status==="Downloading"?<Pause size={16}/>:<Play size={16}/>} {item.status==="Downloading"?"Pause":"Resume"}</button>}<button className="secondary-button" disabled={busy||!online} onClick={()=>void take("remove")}><X size={15}/> Remove</button></div>
    </>:<div className="no-detail"><FolderOpen size={40}/><strong>No download selected</strong><p>Add a URL to see live progress, graphs and file details.</p></div>}
  </Glass>;
  if(detailId)return <div className={"application detail-only "+(isBright?"bright-wall":"")} style={rootStyle}>{wallNode}<header className="app-title" data-tauri-drag-region><Brand/><WindowButtons/></header><main className="detail-page">{detailNode}</main></div>;
  const side=[["All Downloads",Download,counts.all],["Downloading",Activity,counts.active],["Paused",Pause,counts.paused],["Completed",CheckCircle2,counts.completed],["Queued",Clock3,counts.queued]] as const;
  return <div className={"application "+(isBright?"bright-wall":"")} style={rootStyle}>{wallNode}
    <div className="app-shell"><header className="app-title" data-tauri-drag-region><Brand/><div className="top-badges"><span className={online?"connected":"disconnected"}>{online?"● ENGINE CONNECTED":"○ ENGINE OFFLINE"}</span><span>WINDOWS • TAURI + REACT</span></div><WindowButtons/></header>
    <div className="workspace"><Glass className="sidebar"><nav>{side.map(([label,Icon,n])=><button key={label} className={filter===label?"nav-current":""} onClick={()=>setFilter(label)}><Icon size={18}/><span>{label}</span><b>{n}</b></button>)}<div className="category-title">CATEGORIES</div>{data.categories.filter(c=>c.key!=="General").slice(0,7).map(c=><button key={c.key} className={filter==="category:"+c.key?"nav-current category-item":"category-item"} onClick={()=>setFilter("category:"+c.key)}><Folder size={16}/><span>{c.name}</span></button>)}</nav><div className="nav-bottom"><button onClick={()=>{setSettingTab("Wallpapers");setSettings(true)}}><Image size={17}/> Wallpapers</button><button onClick={()=>{setSettingTab("Themes");setSettings(true)}}><Palette size={17}/> Themes & Colors</button><button onClick={()=>{setSettingTab("Effects");setSettings(true)}}><Settings size={17}/> Appearance</button></div></Glass>
    <div className="dashboard-col"><Glass className="toolbar"><div className="toolbar-actions"><button className="toolbar-add" onClick={()=>setAdd(true)}><Plus size={20}/> Add URL</button><button title="Start download" disabled={!item||!online} onClick={()=>void take("start")}><Play size={20}/></button><button title="Pause download" disabled={!item||!online} onClick={()=>void take("pause")}><Pause size={20}/></button><button title="Remove download" disabled={!item||!online} onClick={()=>void take("remove")}><Trash2 size={19}/></button><div className="tool-separator"/><button title="Themes" onClick={()=>setSettings(true)}><Palette size={19}/></button><button disabled={!item} title="Separate detail window" onClick={()=>item&&popout(item.id)}><BarChart3 size={19}/></button></div><span className="plexo-label"><Sparkles size={15}/> PLEXO GLASS</span></Glass>
    <Glass className="download-table"><div className="table-title"><div><h2>{filter.startsWith("category:")?filter.slice(9):filter}</h2><p>{data.downloads.length} downloads</p></div><label className="search"><Search size={16}/><input placeholder="Search downloads…" value={search} onChange={e=>setSearch(e.target.value)}/></label></div><div className="table-columns"><span>FILE NAME</span><span>PROGRESS</span><span>SPEED</span><span>ETA</span><span>STATUS</span></div>
      <div className="table-body">{filtered.map(d=><button key={d.id} className={"download-row "+(item?.id===d.id?"row-current":"")} onClick={()=>{setChosen(d.id);setTab("General")}}><span className="file-name"><IconFor file={d.file}/><span><strong title={d.file}>{d.file}</strong><small>{human(d.downloaded)} of {human(d.size)}</small></span></span><span className="progress-column"><MiniBars percent={pct(d)}/><small>{pct(d).toFixed(0)}%</small></span><span>{d.status==="Downloading"?speed(d.speed):"—"}</span><span>{eta(d)}</span><Badge value={d.status}/></button>)}
      {!filtered.length&&<div className="empty-table"><FolderOpen size={38}/><strong>{!online?"Connecting to download engine":data.downloads.length?"No matching downloads":"Your downloads appear here"}</strong><p>{!online?notice:data.downloads.length?"Change the filter or search term.":"Click Add URL to start your first download."}</p>{online&&!data.downloads.length&&<button className="primary-button" onClick={()=>setAdd(true)}><Plus size={16}/> Add URL</button>}</div>}</div>
    </Glass><Glass className="statusbar"><div className="speed-stat"><Activity size={24}/><span><small>TOTAL SPEED</small><strong>{speed(data.speed)}</strong></span></div><Graph small values={history}/><div><small>ACTIVE</small><strong>{counts.active}</strong></div><div><small>COMPLETED</small><strong>{counts.completed}</strong></div></Glass></div>{detailNode}</div>
    <footer className="footer"><span className={online?"footer-online":""}>{notice}</span><span>V0.1 • Connected to the real Rust download engine</span></footer></div>
    {add&&<div className="overlay" onMouseDown={e=>{if(e.currentTarget===e.target)setAdd(false)}}><Glass className="modal add-modal"><div className="modal-header"><h2><Link2 size={22}/> Add download</h2><button onClick={()=>setAdd(false)}><X size={20}/></button></div><p>Send a new file to the original Rust download engine.</p><label className="field">URL<input autoFocus value={input} placeholder="https://example.com/download.zip" onChange={e=>setInput(e.target.value)} onKeyDown={e=>{if(e.key==="Enter")void addLink()}}/></label>{error&&<p className="error-message">{error}</p>}<div className="modal-actions"><button className="secondary-button" onClick={()=>setAdd(false)}>Cancel</button><button disabled={busy||!online} className="primary-button" onClick={()=>void addLink()}><Plus size={17}/> Download</button></div></Glass></div>}
    {settings&&<div className="overlay" onMouseDown={e=>{if(e.currentTarget===e.target)setSettings(false)}}><Glass className="modal appearance-modal"><div className="modal-header"><h2><Palette size={22}/> Themes & Appearance</h2><button onClick={()=>setSettings(false)}><X size={20}/></button></div><div className="setting-tabs">{["Themes","Wallpapers","Effects"].map(t=><button key={t} className={settingTab===t?"current":""} onClick={()=>setSettingTab(t)}>{t}</button>)}</div>
      {settingTab==="Themes"&&<><p>Change the accent color across panels, buttons, progress bars, and live graphs.</p><div className="theme-tiles">{themes.map(t=><button key={t.id} className={theme===t.id?"theme-picked":""} style={{"--tile-accent":t.color,"--tile-secondary":t.secondary} as CSSProperties} onClick={()=>setTheme(t.id)}><span className="theme-landscape"/><span>{t.name}</span>{theme===t.id&&<Check size={17}/>}</button>)}</div></>}
      {settingTab==="Wallpapers"&&<><p>Choose separate image or muted, looping video wallpapers for the main and download-detail windows.</p>{(["main","details"] as const).map(target=>{const path=target==="main"?wallMain:wallDetail;return <div className="wall-option" key={target}><span><strong>{target==="main"?"Main dashboard":"Download windows"}</strong><small>{path?path.split(/[\\/]/).pop():"Default Alpine wallpaper"}</small></span><button className="secondary-button" onClick={()=>void pickWall(target)}><Image size={15}/> Choose image / video</button>{path&&<button title="Reset wallpaper" className="bare-button" onClick={()=>target==="main"?setWallMain(""):setWallDetail("")}><X size={17}/></button>}</div>})}<p className="support-note"><Video size={15}/> PNG, JPG, WebP, MP4, WebM, MOV; videos play silently. Selected files are copied into app data.</p></>}
      {settingTab==="Effects"&&<><p>Live adjustment of background appearance. Panels automatically increase contrast over bright images.</p>{([["Wallpaper dim",dim,setDim,0,80],["Wallpaper blur",blur,setBlur,0,18],["Glass opacity",opacity,setOpacity,30,90]] as const).map(([label,value,setter,min,max])=><label className="slider-control" key={label}><span>{label}<strong>{value}{label==="Wallpaper blur"?" px":"%"}</strong></span><input type="range" min={min} max={max} value={value} onChange={e=>setter(Number(e.target.value))}/></label>)}<div className="sample-glass">Frosted glass preview • Readable on wallpapers</div></>}
      {error&&<div className="error-message">{error}</div>}<div className="modal-actions"><button onClick={()=>setSettings(false)} className="primary-button"><Check size={17}/> Done</button></div>
    </Glass></div>}
  </div>;
}
