import { invoke } from "@tauri-apps/api/core";
import { useEffect, useMemo, useState } from "react";
import type { CSSProperties } from "react";
import { Activity, CheckCircle2, Clock3, Gauge, HardDrive, Pause, Play, Save, Shield, X } from "lucide-react";
import {
  CrystalWindow, WindowTop, ChunkMap, GradientBar, SpeedGraph, pct, units, rate, timeLeft,
  PROGRESS_GRADIENT, progressColor
} from "./CrystalShared";
import type { Dashboard, Download as FileDownload, DownloadVisual, VisualDashboard } from "./CrystalShared";

type Tab = "Download status" | "Speed Limiter" | "Options on completion";
type Limit = { own_limit_kb: number | null; is_torrent: boolean; file: string };
type OriginalSettings = {show_complete:boolean};
const available = (s:string|null|undefined)=>s?.trim()||"Unavailable";
const boolText = (b:boolean|null|undefined)=>b===true?"Yes":b===false?"No":"Unknown";
const regionName=(code:string|null|undefined)=>{
  if(!code)return "Unavailable";
  try{return new Intl.DisplayNames(["en"],{type:"region"}).of(code)??code}
  catch{return code}
};
const flag=(code:string|null|undefined)=>{
  if(!code||!/^[A-Z]{2}$/.test(code))return "🌐";
  return String.fromCodePoint(...Array.from(code).map(c=>127397+c.charCodeAt(0)));
};
function Field({name,value,title}:{name:string;value:string;title?:string}){
  return <div className="cg-metadata-row"><span>{name}</span><strong title={title??value}>{value}</strong></div>;
}
export default function CrystalProgress({ id }:{id:number}){
  const [item,setItem]=useState<FileDownload|null>(null);
  const [visual,setVisual]=useState<DownloadVisual|null>(null);
  const [tab,setTab]=useState<Tab>("Download status");
  const [values,setValues]=useState<number[]>([]);
  const [limit,setLimit]=useState<Limit|null>(null);
  const [limitEnabled,setLimitEnabled]=useState(false);
  const [speedKb,setSpeedKb]=useState("512");
  const [cfg,setCfg]=useState<OriginalSettings|null>(null);
  const [error,setError]=useState(""),[busy,setBusy]=useState(false);
  useEffect(()=>{
    let mounted=true;
    async function load(){
      try{
        const [data,telemetry]=await Promise.all([
          invoke<Dashboard>("dashboard_snapshot"),
          invoke<VisualDashboard>("dashboard_visuals").catch(()=>null)
        ]);
        if(!mounted)return;
        const current=data.downloads.find(d=>d.id===id)??null;
        setItem(current);
        setVisual(telemetry?.downloads.find(d=>d.id===id)??null);
        if(current)setValues(old=>[...old.slice(-55),current.speed]);
      }catch(e){if(mounted)setError(String(e))}
    }
    void load();
    const timer=window.setInterval(()=>void load(),1200);
    void invoke<Limit>("file_operation",{id,operation:"details",value:null})
      .then(r=>{if(!mounted)return;setLimit(r);setLimitEnabled(r.own_limit_kb!==null);
        if(r.own_limit_kb!==null)setSpeedKb(String(r.own_limit_kb));
      }).catch(e=>{if(mounted)setError(String(e))});
    void invoke<OriginalSettings>("glass_settings")
      .then(r=>{if(mounted)setCfg(r)}).catch(()=>undefined);
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
        const n=Number(speedKb);
        if(!Number.isInteger(n)||n<1||n>10_000_000)throw Error("Enter 1–10,000,000 KB/s.");
        await invoke("file_operation",{id,operation:"speed-limit",value:String(n)});
      }else await invoke("file_operation",{id,operation:"speed-limit",value:"off"});
      setLimit(old=>old?{...old,own_limit_kb:limitEnabled?Number(speedKb):null}:old);
    }catch(e){setError(String(e))}finally{setBusy(false)}
  };
  const changeCompletion=async(on:boolean)=>{
    setBusy(true);setError("");
    try{await invoke("update_glass_setting",{key:"show_complete",value:String(on)});
      setCfg({show_complete:on})}catch(e){setError(String(e))}finally{setBusy(false)}
  };
  const percentage=item?pct(item):0;
  const server=visual?.server;
  const serverCountry=useMemo(()=>regionName(server?.country_code),[server?.country_code]);
  const ringColor=progressColor(percentage/100);
  const ringStyle={
    background:`conic-gradient(from -90deg, #243985 0%, #477af4 ${percentage*.52}%, ${ringColor} ${percentage}%, rgba(93,136,161,.20) ${percentage}% 100%)`,
    "--percent":percentage+"%"
  } as CSSProperties;
  return <CrystalWindow target="details"><WindowTop title={`${item?.file??"Download"} — Download Progress`}/>
    <nav className="cg-page-tabs">{(["Download status","Speed Limiter","Options on completion"] as Tab[]).map(t=>
      <button key={t} className={tab===t?"active":""} onClick={()=>setTab(t)}>{t}</button>
    )}</nav>
    <main className="cg-page cg-progress-page-root">
      {!item?<div className="cg-empty"><HardDrive size={32}/><strong>No download with this ID</strong>
        <p>Waiting for the original MDM downloader to report this file.</p></div>:<>
        {tab==="Download status"&&<div className="cg-progress-page">
          <section className="cg-glass cg-progress-summary cg-download-summary">
            <div className="cg-donut" style={ringStyle}><strong>{percentage.toFixed(0)}%</strong></div>
            <div className="cg-summary-info">
              <h2 title={item.file}>{item.file}</h2>
              <p>{units(item.downloaded)} of {units(item.size)} • {item.category}<br/>
                <span className="cg-muted">Current status: </span><strong>{item.status}</strong>
                {item.error&&<span className="cg-error">{item.error}</span>}
              </p>
            </div>
          </section>
          <section className="cg-glass cg-progress-section">
            <div className="cg-section-title"><h3>Total download completion</h3>
              <small>{percentage.toFixed(2)}% of the file</small></div>
            <GradientBar percent={percentage} showLabel/>
            <div className="cg-section-title" style={{marginTop:14}}>
              <h3>Real download chunks / segments</h3>
              <small>{visual?.segments?.length??0} engine segments</small></div>
            <ChunkMap segments={visual?.segments} size={item.size}/>
            <div className="cg-muted" style={{fontSize:10,marginTop:7}}>
              Individual blocks represent real byte ranges reported by the Rust engine, not the overall percentage.
            </div>
          </section>
          <div className="cg-progress-details">
            <div className="cg-stat"><small><Activity size={13}/> Transfer speed</small><strong>{rate(item.speed)}</strong></div>
            <div className="cg-stat"><small><Clock3 size={13}/> Time left</small><strong>{timeLeft(item)}</strong></div>
            <div className="cg-stat"><small><HardDrive size={13}/> File size</small><strong>{units(item.size)}</strong></div>
          </div>
          <section className="cg-glass cg-progress-section cg-live-graph">
            <div className="cg-section-title"><h3>Live transfer speed</h3><small>{rate(item.speed)}</small></div>
            <SpeedGraph values={values}/>
          </section>
          <section className="cg-glass cg-progress-section cg-details-panel">
            <div className="cg-section-title"><h3>Original MDM download details</h3>
              <small>Live or last observed by Rust engine</small></div>
            <div className="cg-metadata-grid">
              <div>
                <Field name="File name" value={item.file}/>
                <Field name="Save to" value={item.path} title={item.path}/>
                <Field name="Category" value={item.category}/>
                <Field name="Downloaded" value={`${units(item.downloaded)} (${percentage.toFixed(2)}%)`}/>
                <Field name="Total size" value={units(item.size)}/>
                <Field name="Transfer rate" value={rate(item.speed)}/>
                <Field name="Time left" value={timeLeft(item)}/>
                <Field name="Status" value={item.status}/>
                <Field name="Resume capability" value={boolText(visual?.resumable)}/>
                <Field name="Connections" value={visual?String(visual.connections.length):"Unavailable"}/>
              </div>
              <div>
                <Field name="Server" value={available(server?.hostname)}/>
                <Field name="Server IP" value={available(server?.ip)}/>
                <Field name="Country" value={server?.country_code?`${flag(server.country_code)} ${serverCountry}`:"Unavailable"}/>
                <Field name="Round-trip latency" value={server?.rtt_ms!=null?`${server.rtt_ms} ms`:"Unavailable"}/>
                <Field name="CDN" value={available(server?.cdn)}/>
                <Field name="Proxy" value={server?.proxied?"Yes":"No / not detected"}/>
                <Field name="Added" value={available(visual?.added??item.added)}/>
                <Field name="Last try" value={available(visual?.last_try)}/>
                <Field name="Referrer" value={available(visual?.referer)} title={visual?.referer??undefined}/>
                <Field name="Download URL" value={item.url} title={item.url}/>
              </div>
            </div>
            <div className="cg-muted" style={{fontSize:10,marginTop:9}}>
              Country is an offline IP-geolocation estimate. The latency is a connection round-trip measured by MDM, not a separate ICMP ping. Some downloads do not expose a single server.
            </div>
          </section>
          {visual?.connections.length? <details className="cg-glass cg-connection-details">
            <summary>Original MDM connection details ({visual.connections.length})</summary>
            <div className="cg-connection-grid">
              <strong>N.</strong><strong>Downloaded</strong><strong>Speed</strong><strong>Info</strong>
              {visual.connections.map(c=><div className="cg-connection-row" key={c.id}>
                <span>{c.id+1}</span><span>{units(c.downloaded)}</span>
                <span>{rate(c.speed)}</span><span>{c.state}</span>
              </div>)}
            </div>
          </details>:null}
        </div>}
        {tab==="Speed Limiter"&&<section className="cg-glass cg-progress-section">
          <div className="cg-section-title"><h3>Original MDM per-download Speed Limiter</h3><Gauge size={18} color="var(--accent)"/></div>
          <p className="cg-muted" style={{fontSize:11,lineHeight:1.7}}>Sets the Rust download engine's real limit for this file, remembered after stop and resume.</p>
          <label className="cg-toggle"><span><strong>Use Speed Limiter</strong><small>Enable a maximum rate for this download</small></span>
            <input type="checkbox" checked={limitEnabled} onChange={e=>setLimitEnabled(e.target.checked)} disabled={busy||!limit}/></label>
          <label className="cg-field" style={{marginTop:16,maxWidth:260}}>Maximum speed (KB/s)
            <input type="number" min="1" max="10000000" value={speedKb}
              disabled={!limitEnabled||busy} onChange={e=>setSpeedKb(e.target.value)}/></label>
          <p className="cg-muted" style={{fontSize:11}}>Current transfer speed: {rate(item.speed)}.</p>
          <button className="cg-btn cg-btn-primary" disabled={busy||!limit}
            onClick={()=>void saveLimit()}><Save size={16}/> Apply Speed Limiter</button>
        </section>}
        {tab==="Options on completion"&&<section className="cg-glass cg-progress-section">
          <div className="cg-section-title"><h3>Original MDM completion options</h3><CheckCircle2 size={18} color="var(--accent)"/></div>
          <p className="cg-muted" style={{fontSize:11,lineHeight:1.6}}>The dialog option below is a real MDM setting and currently affects all downloads.</p>
          <label className="cg-toggle"><span><strong>Show download complete dialog</strong>
            <small>Notify when a transfer finishes</small></span>
            <input type="checkbox" checked={cfg?.show_complete??false} disabled={!cfg||busy}
              onChange={e=>void changeCompletion(e.target.checked)}/></label>
          <label className="cg-toggle"><span><strong>Exit MDM when complete</strong>
            <small>Awaiting the original per-download completion hook</small></span><input type="checkbox" disabled/></label>
          <label className="cg-toggle"><span><strong>Turn off computer when complete</strong>
            <small>Must use the original MDM safety confirmation</small></span><input type="checkbox" disabled/></label>
          <div className="cg-settings-fallback" style={{marginTop:18}}><Shield size={17}/>
            Remaining per-download completion hooks still need backend migration. Disabled controls will not pretend to save settings.</div>
        </section>}
      </>}
      {error&&<p className="cg-error">{error}</p>}
      <div className="cg-bottom-actions" style={{marginTop:12}}>
        {item?.status==="Downloading"?<button className="cg-btn cg-btn-primary" disabled={busy}
          onClick={()=>void action("pause")}><Pause size={17}/> Pause</button>:
          item&&item.status!=="Complete"?<button className="cg-btn cg-btn-primary" disabled={busy}
            onClick={()=>void action("start")}><Play size={17}/> Resume</button>:null}
        <button className="cg-btn" onClick={()=>void import("@tauri-apps/api/window").then(m=>m.getCurrentWindow().close())}>
          <X size={17}/> Close</button>
      </div>
    </main>
  </CrystalWindow>;
}
