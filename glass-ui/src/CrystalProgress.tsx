import CrystalCompletionOptions from './CrystalCompletionOptions';
import { invoke } from '@tauri-apps/api/core';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { useEffect, useRef, useState } from 'react';
import { FileText, Pause, Play, Save } from 'lucide-react';
import { CrystalWindow, CountryFlag, WindowTop, ConnectionMap, GradientBar, SpeedGraph, pct, units, rate, timeLeft, openWindow, useCrystal, indicatorColors } from './CrystalShared';
import {TubeBridge} from './ConnectionTubes';
import {receivingTubeSlots} from './tubeNetwork';
import type { Dashboard, Download, DownloadVisual, VisualDashboard } from './CrystalShared';
type Tab='Download status'|'Speed Limiter'|'Options on completion';
type Limit={own_limit_kb:number|null;is_torrent:boolean};
const country=(code:string|null|undefined)=>{if(!code)return 'Unavailable';try{return new Intl.DisplayNames(['en'],{type:'region'}).of(code)??code}catch{return code}};

export default function CrystalProgress({id}:{id:number}){
 const [item,setItem]=useState<Download|null>(null),[visual,setVisual]=useState<DownloadVisual|null>(null),[tab,setTab]=useState<Tab>('Download status');
 const [values,setValues]=useState<number[]>([]),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const [checking,setChecking]=useState(false),[checkMessage,setCheckMessage]=useState(''),[damaged,setDamaged]=useState(false);
 const [limit,setLimit]=useState<Limit|null>(null),[limited,setLimited]=useState(false),[kb,setKb]=useState('512');
 const pageRef=useRef<HTMLElement>(null),{appearance}=useCrystal();
 useEffect(()=>{
  let active=true,running=false;
  const load=async()=>{if(running)return;running=true;try{const [data,telemetry]=await Promise.all([invoke<Dashboard>('dashboard_snapshot'),invoke<VisualDashboard>('dashboard_visuals')]);if(!active)return;const file=data.downloads.find(d=>d.id===id)??null;setItem(file);setVisual(telemetry.downloads.find(d=>d.id===id)??null);if(file)setValues(v=>[...v.slice(-55),file.speed]);}catch(e){if(active)setError(String(e))}finally{running=false}};
  void load();const timer=setInterval(()=>void load(),1200);
  void invoke<Limit>('file_operation',{id,operation:'details',value:null}).then(l=>{if(active){setLimit(l);setLimited(l.own_limit_kb!=null);if(l.own_limit_kb!=null)setKb(String(l.own_limit_kb))}}).catch(e=>{if(active)setError(String(e))});

  return()=>{active=false;clearInterval(timer)};
 },[id]);
 useEffect(()=>{
  if(!checking)return;let active=true,polling=false;
  const poll=async()=>{if(polling)return;polling=true;try{
   const result=await invoke<{complete:boolean;failure?:string;report?:{checked_bytes:number;unhashed_bytes:number;damaged_ranges:[number,number][]}}>('file_operation',{id,operation:'check-saved-result',value:null});
   if(!active||!result.complete)return;setChecking(false);
   if(result.failure){setError(result.failure);return}
   const report=result.report;if(!report){setError('The saved-data check returned no result.');return}
   const damage=report.damaged_ranges.length;setDamaged(damage>0);
   setCheckMessage(`${units(report.checked_bytes)} checked. ${damage?`${damage} changed range${damage===1?'':'s'} found; saved data was kept and resume is blocked.`:report.checked_bytes?'No changes detected in checked data.':'No saved hashes were available to check.'}${report.unhashed_bytes?` ${units(report.unhashed_bytes)} has no saved hash and could not be checked.`:''} Local hashes do not prove the original download was correct.`);
  }catch(e){if(active){setChecking(false);setError(String(e))}}finally{polling=false}};
  void poll();const timer=setInterval(()=>void poll(),1000);return()=>{active=false;clearInterval(timer)};
 },[checking,id]);
 const checkSaved=async()=>{setError('');setCheckMessage('');setBusy(true);try{await invoke('file_operation',{id,operation:'check-saved',value:null});setChecking(true)}catch(e){setError(String(e))}finally{setBusy(false)}};
 const run=async(action:string)=>{setBusy(true);setError('');try{await invoke('download_action',{action,ids:[id]});if(action==='pause'&&item?.status==='Downloading')setItem({...item,status:'Stopped',speed:0});}catch(e){setError(String(e))}finally{setBusy(false)}};
 const save=async()=>{setBusy(true);setError('');try{const n=Number(kb);if(limited&&(!Number.isInteger(n)||n<1||n>10_000_000))throw Error('Enter 1–10,000,000 KB/sec.');await invoke('file_operation',{id,operation:'speed-limit',value:limited?String(n):'off'});}catch(e){setError(String(e))}finally{setBusy(false)}};
 const server=visual?.server;
 const statusText=item?.status==='Downloading'?(visual?.connections.some(c=>c.state==='Receiving')?'Receiving data…':'Connecting…'):item?.status==='Stopped'?'Paused':item?.status??'Waiting…';
 const metadata=item?[
  ['Status',statusText],['Transfer method',!visual?'Unknown':visual.is_torrent?'Torrent':'Direct download'],['File size',units(item.size)],['Downloaded',`${units(item.downloaded)} (${pct(item).toFixed(2)}%)`],
  ['Transfer rate',item.status==='Downloading'?rate(item.speed):'—'],['Time left',timeLeft(item)],
  ['Resume capability',visual?.resumable===true?'Yes':visual?.resumable===false?'No':'Unknown'],
  ['Server',`${server?.place?.name??country(server?.country_code)}${server?.rtt_ms!=null?` · about ${server.rtt_ms} ms${server.place?.reach?` (${server.place.reach})`:""}`:''}`]
 ]:[];
 return <CrystalWindow target="details"><WindowTop title={`${item?pct(item).toFixed(0)+'% ':''}${item?.file??'Download'}`}/>
  <nav className="cg-page-tabs">{(['Download status','Speed Limiter','Options on completion'] as Tab[]).map(t=><button className={tab===t?'active':''} key={t} onClick={()=>setTab(t)}>{t}</button>)}</nav>
  <main ref={pageRef} className="cg-page cg-minimal-progress cg-piped-progress-page">
   {!item?<div className="cg-empty">Waiting for download information…</div>:tab==='Download status'?<>
    <section className="cg-glass cg-mdm-details"><div className="cg-download-url" title={item.url}>{item.url}</div><dl>{metadata.map(([label,value])=><div key={label}><dt>{label}</dt><dd title={value}>{label==='Server'&&<CountryFlag place={server?.place}/>} {value}</dd></div>)}</dl></section>
    <section className="cg-glass cg-progress-section cg-progress-tube cg-overall"><GradientBar percent={pct(item)} size={item.size} active={item.status==="Downloading"} showLabel/></section>
    <div className="cg-indicator-row"><section className="cg-glass cg-progress-section cg-selected-chunks"><div className="cg-section-title"><h3>Connections</h3></div><ConnectionMap segments={visual?.segments} connections={visual?.connections} downloading={item.status==="Downloading"} paused={item.status==="Stopped"} tubes/></section>
    <section className="cg-glass cg-progress-section cg-progress-combined cg-progress-graph"><div className="cg-compact-speed"><div className="cg-section-title"><h3>Transfer speed</h3><small>{rate(item.speed)} · last {Math.round(values.length*1.2)} sec</small></div><SpeedGraph values={values}/></div></section></div>
    {item.error&&<p className="cg-error">{item.error}</p>}
    {checkMessage&&<p role="status" className="cg-muted">{checkMessage}</p>}
    {checking&&<p role="status" className="cg-muted">Checking saved data…</p>}
   </>:tab==='Speed Limiter'?<section className="cg-glass cg-progress-section"><h3>Speed Limiter</h3><label className="cg-toggle"><span><strong>Use Speed Limiter</strong><small>Remember the limit after pause and resume</small></span><input type="checkbox" checked={limited} disabled={!limit||busy} onChange={e=>setLimited(e.target.checked)}/></label><label className="cg-field">Maximum speed (KB/sec)<input type="number" min="1" value={kb} disabled={!limited||busy} onChange={e=>setKb(e.target.value)}/></label><button className="cg-btn cg-btn-primary" disabled={!limit||busy} onClick={()=>void save()}><Save size={16}/>Apply limit</button></section>:<CrystalCompletionOptions id={id}/>}
   <TubeBridge container={pageRef} ready={!!item&&tab==='Download status'} active={receivingTubeSlots(visual?.connections,item?.status==='Downloading').some(Boolean)} colors={indicatorColors(appearance.connectionIndicator)} progressColors={indicatorColors(appearance.indicator)}/>
   {error&&<p className="cg-error" role="alert">{error}</p>}
   <div className="cg-bottom-actions">{item&&item.status!=='Downloading'&&item.status!=='Complete'&&visual&&!visual.is_torrent&&<button className="cg-btn" disabled={busy||checking} onClick={()=>void checkSaved()}>Check saved data</button>}<button className="cg-btn cg-neon-violet" onClick={()=>openWindow(`properties-${id}`,`/?properties=${id}`,760,600)}><FileText size={15}/>Properties</button><span className="cg-action-space"/>{item?.status==='Downloading'?<button className="cg-btn cg-neon-amber" disabled={busy} onClick={()=>void run('pause')}><Pause size={16}/>Pause</button>:item&&item.status!=='Complete'?<button className="cg-btn cg-neon-mint" disabled={busy||checking||damaged} onClick={()=>void run('start')}><Play size={16}/>Resume</button>:null}<button className="cg-btn cg-btn-danger" disabled={busy} onClick={async()=>{if(item?.status==='Downloading')await run('pause');await getCurrentWindow().close()}}>Cancel</button></div>
  </main></CrystalWindow>;
}
