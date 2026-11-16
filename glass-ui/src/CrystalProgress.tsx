import CrystalCompletionOptions from './CrystalCompletionOptions';
import { invoke } from '@tauri-apps/api/core';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { useEffect, useState } from 'react';
import { FileText, Pause, Play, Save } from 'lucide-react';
import { CrystalWindow, CountryFlag, WindowTop, ChunkMap, GradientBar, SpeedGraph, pct, units, rate, timeLeft, openWindow } from './CrystalShared';
import type { Dashboard, Download, DownloadVisual, VisualDashboard } from './CrystalShared';
type Tab='Download status'|'Speed Limiter'|'Options on completion';
type Limit={own_limit_kb:number|null;is_torrent:boolean};
const country=(code:string|null|undefined)=>{if(!code)return 'Unavailable';try{return new Intl.DisplayNames(['en'],{type:'region'}).of(code)??code}catch{return code}};

export default function CrystalProgress({id}:{id:number}){
 const [item,setItem]=useState<Download|null>(null),[visual,setVisual]=useState<DownloadVisual|null>(null),[tab,setTab]=useState<Tab>('Download status');
 const [values,setValues]=useState<number[]>([]),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const [limit,setLimit]=useState<Limit|null>(null),[limited,setLimited]=useState(false),[kb,setKb]=useState('512');
 const [connectionPage,setConnectionPage]=useState(0);
 const [compactConnections,setCompactConnections]=useState(()=>window.innerHeight<=600);
 useEffect(()=>{const resize=()=>setCompactConnections(window.innerHeight<=600);window.addEventListener('resize',resize);return()=>window.removeEventListener('resize',resize)},[]);
 useEffect(()=>{
  let active=true,running=false;
  const load=async()=>{if(running)return;running=true;try{const [data,telemetry]=await Promise.all([invoke<Dashboard>('dashboard_snapshot'),invoke<VisualDashboard>('dashboard_visuals')]);if(!active)return;const file=data.downloads.find(d=>d.id===id)??null;setItem(file);setVisual(telemetry.downloads.find(d=>d.id===id)??null);if(file)setValues(v=>[...v.slice(-55),file.speed]);}catch(e){if(active)setError(String(e))}finally{running=false}};
  void load();const timer=setInterval(()=>void load(),1200);
  void invoke<Limit>('file_operation',{id,operation:'details',value:null}).then(l=>{if(active){setLimit(l);setLimited(l.own_limit_kb!=null);if(l.own_limit_kb!=null)setKb(String(l.own_limit_kb))}}).catch(e=>{if(active)setError(String(e))});

  return()=>{active=false;clearInterval(timer)};
 },[id]);
 const run=async(action:string)=>{setBusy(true);setError('');try{await invoke('download_action',{action,ids:[id]});if(action==='pause'&&item?.status==='Downloading')setItem({...item,status:'Stopped',speed:0});}catch(e){setError(String(e))}finally{setBusy(false)}};
 const save=async()=>{setBusy(true);setError('');try{const n=Number(kb);if(limited&&(!Number.isInteger(n)||n<1||n>10_000_000))throw Error('Enter 1–10,000,000 KB/sec.');await invoke('file_operation',{id,operation:'speed-limit',value:limited?String(n):'off'});}catch(e){setError(String(e))}finally{setBusy(false)}};
 const server=visual?.server;
 const connectionCount=visual?.connections.length??0;
 const pageSize=compactConnections?2:8;
 const pages=Math.max(1,Math.ceil(connectionCount/pageSize)),page=Math.min(connectionPage,pages-1);
 const statusText=item?.status==='Downloading'?(visual?.connections.some(c=>c.state==='Receiving')?'Receiving data…':'Connecting…'):item?.status==='Stopped'?'Paused':item?.status??'Waiting…';
 const metadata=item?[
  ['Status',statusText],['File size',units(item.size)],['Downloaded',`${units(item.downloaded)} (${pct(item).toFixed(2)}%)`],
  ['Transfer rate',item.status==='Downloading'?rate(item.speed):'—'],['Time left',timeLeft(item)],
  ['Resume capability',visual?.resumable===true?'Yes':visual?.resumable===false?'No':'Unknown'],
  ['Server',`${server?.place?.name??country(server?.country_code)}${server?.rtt_ms!=null?` · about ${server.rtt_ms} ms${server.place?.reach?` (${server.place.reach})`:""}`:''}`]
 ]:[];
 return <CrystalWindow target="details"><WindowTop title={`${item?pct(item).toFixed(0)+'% ':''}${item?.file??'Download'}`}/>
  <nav className="cg-page-tabs">{(['Download status','Speed Limiter','Options on completion'] as Tab[]).map(t=><button className={tab===t?'active':''} key={t} onClick={()=>setTab(t)}>{t}</button>)}</nav>
  <main className="cg-page cg-minimal-progress">
   {!item?<div className="cg-empty">Waiting for download information…</div>:tab==='Download status'?<>
    <section className="cg-glass cg-mdm-details"><div className="cg-download-url" title={item.url}>{item.url}</div><dl>{metadata.map(([label,value])=><div key={label}><dt>{label}</dt><dd title={value}>{label==='Server'&&<CountryFlag place={server?.place}/>} {value}</dd></div>)}</dl></section>
    <div className="cg-indicator-row"><section className="cg-glass cg-progress-section cg-progress-combined"><div className="cg-overall"><GradientBar percent={pct(item)} showLabel/></div><div className="cg-compact-speed"><div className="cg-section-title"><h3>Transfer speed</h3><small>{rate(item.speed)} · last {Math.round(values.length*1.2)} sec</small></div><SpeedGraph values={values}/></div></section>
    <section className="cg-glass cg-progress-section cg-selected-chunks"><div className="cg-section-title"><h3>Download chunks</h3></div><ChunkMap segments={visual?.segments} size={item.size} count={visual?.chunk_count} active={visual?.active_connections}/>
     <details className="cg-connection-details"><summary>Connection details ({connectionCount})</summary>
      <table className="cg-connections"><thead><tr><th>N.</th><th>Downloaded</th><th>Speed</th><th>Info</th></tr></thead><tbody>{visual?.connections.slice(page*pageSize,page*pageSize+pageSize).map(c=><tr key={c.id}><td>{c.id+1}</td><td>{units(c.downloaded)}</td><td>{rate(c.speed)}</td><td>{c.state}</td></tr>)}</tbody></table>
      {pages>1&&<div className="cg-pagination"><button disabled={!page} onClick={()=>setConnectionPage(p=>p-1)}>Previous</button><span>{page+1} / {pages}</span><button disabled={page>=pages-1} onClick={()=>setConnectionPage(p=>p+1)}>Next</button></div>}
     </details>
    </section></div>
    {item.error&&<p className="cg-error">{item.error}</p>}
   </>:tab==='Speed Limiter'?<section className="cg-glass cg-progress-section"><h3>Speed Limiter</h3><label className="cg-toggle"><span><strong>Use Speed Limiter</strong><small>Remember the limit after pause and resume</small></span><input type="checkbox" checked={limited} disabled={!limit||busy} onChange={e=>setLimited(e.target.checked)}/></label><label className="cg-field">Maximum speed (KB/sec)<input type="number" min="1" value={kb} disabled={!limited||busy} onChange={e=>setKb(e.target.value)}/></label><button className="cg-btn cg-btn-primary" disabled={!limit||busy} onClick={()=>void save()}><Save size={16}/>Apply limit</button></section>:<CrystalCompletionOptions id={id}/>}
   {error&&<p className="cg-error" role="alert">{error}</p>}
   <div className="cg-bottom-actions"><button className="cg-btn cg-neon-violet" onClick={()=>openWindow(`properties-${id}`,`/?properties=${id}`,760,600)}><FileText size={15}/>Properties</button><span className="cg-action-space"/>{item?.status==='Downloading'?<button className="cg-btn cg-neon-amber" disabled={busy} onClick={()=>void run('pause')}><Pause size={16}/>Pause</button>:item&&item.status!=='Complete'?<button className="cg-btn cg-neon-mint" disabled={busy} onClick={()=>void run('start')}><Play size={16}/>Resume</button>:null}<button className="cg-btn cg-btn-danger" disabled={busy} onClick={async()=>{if(item?.status==='Downloading')await run('pause');await getCurrentWindow().close()}}>Cancel</button></div>
  </main></CrystalWindow>;
}
