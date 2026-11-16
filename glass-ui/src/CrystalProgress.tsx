import { invoke } from "@tauri-apps/api/core";
import { useEffect, useState } from "react";
import { Activity, CheckCircle2, Clock3, Download, Folder, Gauge, HardDrive, Pause, Play, Save, Shield, X } from "lucide-react";
import {
  CrystalWindow, WindowTop, FlowMatrix, GradientBar, SpeedGraph, pct, units, rate, timeLeft,
  progressGradient, useCrystal
} from "./CrystalShared";
import type { Dashboard, Download as FileDownload } from "./CrystalShared";

type Tab = "Download status" | "Speed Limiter" | "Options on completion";
type Limit = { own_limit_kb: number | null; is_torrent: boolean; file: string };
export default function CrystalProgress({ id }: { id: number }) {
  const [item, setItem] = useState<FileDownload | null>(null);
  const [tab, setTab] = useState<Tab>("Download status");
  const [values, setValues] = useState<number[]>([]);
  const [limit, setLimit] = useState<Limit | null>(null);
  const [limitEnabled, setLimitEnabled] = useState(false);
  const [speedKb, setSpeedKb] = useState("512");
  const [cfg, setCfg] = useState<{show_complete:boolean}|null>(null);
  const [error, setError] = useState(""), [busy, setBusy] = useState(false);
  const {theme}=useCrystal();
  useEffect(() => {
    let mounted = true;
    async function load() {
      try{
        const d=await invoke<Dashboard>("dashboard_snapshot");
        if (!mounted) return;
        const current=d.downloads.find(x=>x.id===id);
        setItem(current??null);
        if(current) setValues(v=>[...v.slice(-54),current.speed]);
      }catch(e){if(mounted)setError(String(e))}
    }
    void load();const timer=window.setInterval(()=>void load(),1150);
    void invoke<Limit>("file_operation",{id,operation:"details",value:null}).then(r=>{
      if(!mounted)return;
      setLimit(r);setLimitEnabled(r.own_limit_kb!==null);
      if(r.own_limit_kb!==null)setSpeedKb(String(r.own_limit_kb));
    }).catch(e=>{if(mounted)setError(String(e))});
    void invoke<{show_complete:boolean}>("glass_settings").then(r=>{if(mounted)setCfg(r)}).catch(()=>undefined);
    return()=>{mounted=false;window.clearInterval(timer)};
  },[id]);
  const action=async(name:"start"|"pause")=>{
    setBusy(true);setError("");
    try{await invoke("download_action",{action:name,ids:[id]})}
    catch(e){setError(String(e))}finally{setBusy(false)}
  };
  const saveLimit=async()=>{
    setBusy(true);setError("");
    try{
      if(limitEnabled){
        const number=Number(speedKb);
        if(!Number.isInteger(number)||number<1||number>10000000){
          throw Error("Enter a speed between 1 and 10,000,000 KB/s.");
        }
        await invoke("file_operation",{id,operation:"speed-limit",value:String(number)});
      }else await invoke("file_operation",{id,operation:"speed-limit",value:"off"});
      setLimit(prev=>prev?{...prev,own_limit_kb:limitEnabled?Number(speedKb):null}:prev);
    }catch(e){setError(String(e))}finally{setBusy(false)}
  };
  const changeCompletion=async(on:boolean)=>{
    setBusy(true);setError("");
    try{
      await invoke("update_glass_setting",{key:"show_complete",value:String(on)});
      setCfg({show_complete:on});
    }catch(e){setError(String(e))}finally{setBusy(false)}
  };
  const percent=item?pct(item):0;
  return <CrystalWindow target="details"><WindowTop title={`${item?.file??"Download"} — Download Progress`}/>
    <nav className="cg-page-tabs">{(["Download status","Speed Limiter","Options on completion"] as Tab[]).map(t=>
      <button key={t} className={tab===t?"active":""} onClick={()=>setTab(t)}>{t}</button>
    )}</nav>
    <main className="cg-page">
      {!item?<div className="cg-empty"><HardDrive size={33}/><strong>No download with this ID</strong>
        <p>This window will update when the Rust download engine reports the file.</p></div>:<>
        {tab==="Download status"&&<div className="cg-progress-page">
          <section className="cg-glass cg-progress-summary">
            <div className="cg-donut" style={{"--percent":`${percent}%`,background:`conic-gradient(${theme.accent} ${percent}%,rgba(97,152,171,.21) 0)`} as React.CSSProperties}>
              <strong>{percent.toFixed(0)}%</strong>
            </div>
            <div><h2>{item.file}</h2><p>
              {units(item.downloaded)} / {units(item.size)}<br/>
              <span style={{color:"var(--accent)"}}>{item.status}</span> • {item.category}
            </p></div>
          </section>
          <section className="cg-glass cg-progress-section">
            <div className="cg-section-title"><h3>Download progress</h3><small>{percent.toFixed(1)}% complete</small></div>
            <div style={{height:9,borderRadius:10,background:"rgba(82,140,157,.24)",overflow:"hidden",marginBottom:12}}>
              <div style={{height:"100%",width:`${percent}%`,background:progressGradient(percent,theme.accent),borderRadius:10,transition:"width .45s ease,background .45s ease"}}/>
            </div>
            <FlowMatrix percent={percent}/>
            <div style={{marginTop:11,display:"flex",alignItems:"center",gap:12}}>
              <span style={{width:140}}><GradientBar percent={percent} showLabel/></span>
              <span className="cg-muted" style={{fontSize:10}}>Dynamic color progression • decorative blocks</span>
            </div>
          </section>
          <div className="cg-progress-details">
            <div className="cg-stat"><small><Activity size={13}/> Transfer speed</small><strong>{rate(item.speed)}</strong></div>
            <div className="cg-stat"><small><Clock3 size={13}/> Remaining time</small><strong>{timeLeft(item)}</strong></div>
            <div className="cg-stat"><small><HardDrive size={13}/> File size</small><strong>{units(item.size)}</strong></div>
          </div>
          <section className="cg-glass cg-progress-section">
            <div className="cg-section-title"><h3>Live transfer speed</h3><small>{rate(item.speed)}</small></div>
            <SpeedGraph values={values}/>
          </section>
          <section className="cg-glass cg-progress-section" style={{fontSize:10,lineHeight:1.8}}>
            <div><span className="cg-muted">Download URL: </span><span title={item.url}>{item.url.length>85?item.url.slice(0,85)+"…":item.url}</span></div>
            <div><span className="cg-muted">Save to: </span><span title={item.path}>{item.path}</span></div>
          </section>
        </div>}
        {tab==="Speed Limiter"&&<section className="cg-glass cg-progress-section">
          <div className="cg-section-title"><h3>Per-download Speed Limiter</h3><Gauge size={18} color="var(--accent)"/></div>
          <p className="cg-muted" style={{fontSize:11,lineHeight:1.7}}>This is the original Rust download engine's real, per-file speed limiter. Its limit is remembered after stop and resume.</p>
          <label className="cg-toggle"><span><strong>Use Speed Limiter</strong><small>Enable a maximum transfer rate for this file</small></span>
            <input type="checkbox" checked={limitEnabled} onChange={e=>setLimitEnabled(e.target.checked)} disabled={busy||!limit}/>
          </label>
          <label className="cg-field" style={{marginTop:16,maxWidth:260}}>Maximum download speed (KB/s)
            <input type="number" min="1" max="10000000" value={speedKb} disabled={!limitEnabled||busy}
              onChange={e=>setSpeedKb(e.target.value)}/></label>
          <p className="cg-muted" style={{fontSize:11}}>Current transfer speed: {rate(item.speed)}. Turn off to restore the global speed limit, if enabled.</p>
          <button className="cg-btn cg-btn-primary" disabled={busy||!limit} onClick={()=>void saveLimit()}><Save size={16}/> Apply Speed Limiter</button>
        </section>}
        {tab==="Options on completion"&&<section className="cg-glass cg-progress-section">
          <div className="cg-section-title"><h3>Options on completion</h3><CheckCircle2 size={18} color="var(--accent)"/></div>
          <p className="cg-muted" style={{fontSize:11,lineHeight:1.6}}>Completion behavior of Mister Download Manager. These settings currently affect the download manager globally.</p>
          <label className="cg-toggle"><span><strong>Show download complete dialog</strong><small>Display a notification when a download finishes</small></span>
            <input type="checkbox" checked={cfg?.show_complete??false} disabled={!cfg||busy}
              onChange={e=>void changeCompletion(e.target.checked)}/></label>
          <label className="cg-toggle"><span><strong>Exit MDM when complete</strong><small>Requires the original per-download completion hook to be migrated</small></span><input type="checkbox" disabled/></label>
          <label className="cg-toggle"><span><strong>Turn off computer when complete</strong><small>Disabled until the original completion behavior is safely integrated</small></span><input type="checkbox" disabled/></label>
          <div className="cg-settings-fallback" style={{marginTop:18}}><Shield size={17}/> Unsupported completion actions are deliberately disabled rather than pretending they work.</div>
        </section>}
      </>}
      {error&&<p className="cg-error">{error}</p>}
      <div className="cg-bottom-actions" style={{marginTop:14}}>
        {item?.status==="Downloading"?<button className="cg-btn cg-btn-primary" disabled={busy} onClick={()=>void action("pause")}><Pause size={17}/> Pause</button>:
          item&&item.status!=="Complete"?<button className="cg-btn cg-btn-primary" disabled={busy} onClick={()=>void action("start")}><Play size={17}/> Resume</button>:null}
        <button className="cg-btn" onClick={()=>void import("@tauri-apps/api/window").then(m=>m.getCurrentWindow().close())}><X size={17}/> Close</button>
      </div>
    </main>
  </CrystalWindow>;
}
