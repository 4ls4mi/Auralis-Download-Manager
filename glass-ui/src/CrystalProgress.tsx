import CrystalCompletionOptions from './CrystalCompletionOptions';
import { invoke } from '@tauri-apps/api/core';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { useEffect, useRef, useState } from 'react';
import { FileText, Network, Pause, Play, Save } from 'lucide-react';
import { CrystalWindow, CountryFlag, WindowTop, ConnectionMap, GradientBar, SpeedGraph, pct, units, rate, timeLeft, openWindow, useCrystal, indicatorColors } from './CrystalShared';
import {TubeBridge} from './ConnectionTubes';
import {receivingTubeSlots} from './tubeNetwork';
import type { Dashboard, Download, DownloadVisual, VisualDashboard } from './CrystalShared';
type Tab='Download status'|'Speed Limiter'|'Options on completion';
type Limit={own_limit_kb:number|null;is_torrent:boolean;checksum?:string|null};
type TorrentSearchResult={complete:boolean;failure?:string;searched?:number;failed?:number;matches?:{candidate:number;file_index:number;info_hash:string;title:string;path:string;matching_pieces:number;unavailable_pieces:number}[]};
type TorrentHandoffResult={complete:boolean;failure?:string;report?:{verified_bytes:number;path:string}};
type SearchMethod='archive'|'torrent-file'|'magnet'|'url';
const country=(code:string|null|undefined)=>{if(!code)return 'Unavailable';try{return new Intl.DisplayNames(['en'],{type:'region'}).of(code)??code}catch{return code}};

export default function CrystalProgress({id}:{id:number}){
 const [item,setItem]=useState<Download|null>(null),[visual,setVisual]=useState<DownloadVisual|null>(null),[tab,setTab]=useState<Tab>('Download status');
 const [values,setValues]=useState<number[]>([]),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const [checking,setChecking]=useState(false),[checkMessage,setCheckMessage]=useState(''),[damaged,setDamaged]=useState(false);
 const [repairing,setRepairing]=useState(false);
 const [searching,setSearching]=useState(false),[torrentSearch,setTorrentSearch]=useState<TorrentSearchResult|null>(null);
 const [torrentLink,setTorrentLink]=useState(''),[searchMethod,setSearchMethod]=useState<SearchMethod|null>(null);
 const [searchActionError,setSearchActionError]=useState('');
 const [acceptTorrentRisk,setAcceptTorrentRisk]=useState(false),[preparingTorrent,setPreparingTorrent]=useState(false),[handoff,setHandoff]=useState<TorrentHandoffResult|null>(null);
 const [limit,setLimit]=useState<Limit|null>(null),[limited,setLimited]=useState(false),[kb,setKb]=useState('512');
 const pageRef=useRef<HTMLElement>(null),{appearance}=useCrystal();
 useEffect(()=>{
  let active=true,running=false;
  const load=async()=>{if(running)return;running=true;try{const [data,telemetry]=await Promise.all([invoke<Dashboard>('dashboard_snapshot'),invoke<VisualDashboard>('dashboard_visuals')]);if(!active)return;const file=data.downloads.find(d=>d.id===id)??null;setItem(file);setVisual(telemetry.downloads.find(d=>d.id===id)??null);if(file)setValues(v=>[...v.slice(-55),file.speed]);}catch(e){if(active)setError(String(e))}finally{running=false}};
  void load();const timer=setInterval(()=>void load(),1200);
  void invoke<Limit>('file_operation',{id,operation:'details',value:null}).then(l=>{if(active){setLimit(l);setLimited(l.own_limit_kb!=null);if(l.own_limit_kb!=null)setKb(String(l.own_limit_kb))}}).catch(e=>{if(active)setError(String(e))});

  return()=>{active=false;clearInterval(timer)};
 },[id]);
 const searchAvailable=Boolean(visual?.recovery_search_available),handoffAvailable=Boolean(visual?.recovery_handoff_available);
 useEffect(()=>{
  if(searchAvailable)setSearching(true);
  else {setSearching(false);setTorrentSearch(null);setAcceptTorrentRisk(false);setSearchMethod(null);setSearchActionError('')}
 },[id,searchAvailable]);
 useEffect(()=>{
  if(handoffAvailable)setPreparingTorrent(true);
  else {setPreparingTorrent(false);setHandoff(null);}
 },[id,handoffAvailable]);
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
 useEffect(()=>{
  if(!repairing)return;let active=true,polling=false;
  const poll=async()=>{if(polling)return;polling=true;try{
   const result=await invoke<{complete:boolean;failure?:string;report?:{retained_bytes:number;unhashed_bytes:number;damaged_ranges:[number,number][]}}>('file_operation',{id,operation:'repair-saved-result',value:null});
   if(!active||!result.complete)return;setRepairing(false);if(result.failure){setError(result.failure);return}if(!result.report){setError('The repair check returned no result.');return}
   setDamaged(false);setCheckMessage(`The source was checked. ${result.report.damaged_ranges.length} changed range(s) are ready to download again; ${units(result.report.retained_bytes)} was retained. Press Resume to continue.${result.report.unhashed_bytes?` ${units(result.report.unhashed_bytes)} has no saved hash and could not be checked.`:''}`);
  }catch(e){if(active){setRepairing(false);setError(String(e))}}finally{polling=false}};
  void poll();const timer=setInterval(()=>void poll(),1000);return()=>{active=false;clearInterval(timer)};
 },[repairing,id]);
 const repairSaved=async()=>{setError('');setCheckMessage('');setBusy(true);try{await invoke('file_operation',{id,operation:'repair-saved',value:null});setRepairing(true)}catch(e){setError(String(e))}finally{setBusy(false)}};
 useEffect(()=>{
  if(!searching)return;
  let active=true,polling=false;
  const poll=async()=>{if(polling)return;polling=true;try{
   const result=await invoke<TorrentSearchResult>('file_operation',{id,operation:'find-recovery-torrents-result',value:null});
   if(active&&result.complete){setSearching(false);setTorrentSearch(result)}
  }catch(e){if(active){setSearching(false);setTorrentSearch({complete:true,failure:String(e)})}}finally{polling=false}};
  void poll();const timer=setInterval(()=>void poll(),1000);return()=>{active=false;clearInterval(timer)};
 },[searching,id]);
 const startTorrentSearch=async(method:SearchMethod,value:string|null=null)=>{
  setSearchActionError('');setBusy(true);
  try{
   if(method==='torrent-file'){
    const selected=await invoke<{pending:boolean}|null>('choose_recovery_torrent',{id});
    if(!selected)return;
   }else{
    const operation=method==='archive'?'find-recovery-torrents':method==='magnet'?'check-recovery-magnet':'check-recovery-torrent-url';
    await invoke('file_operation',{id,operation,value});
   }
   setSearchMethod(method);setAcceptTorrentRisk(false);setTorrentSearch(null);setHandoff(null);setSearching(true);
  }catch(e){setSearchActionError(String(e))}finally{setBusy(false)}
 };
 const checkTorrentLink=async()=>{
  const value=torrentLink.trim();
  const scheme=value.match(/^([a-z][a-z0-9+.-]*):/i)?.[1].toLowerCase();
  if(scheme==='magnet')await startTorrentSearch('magnet',value);
  else if(scheme==='https'||scheme==='http')await startTorrentSearch('url',value);
  else setSearchActionError('Enter a magnet link or an HTTPS or HTTP link to a torrent file.');
 };
 useEffect(()=>{
  if(!preparingTorrent)return;
  let active=true,polling=false;
  const poll=async()=>{if(polling)return;polling=true;try{
   const result=await invoke<TorrentHandoffResult>('file_operation',{id,operation:'start-recovery-torrent-result',value:null});
   if(active&&result.complete){
    setPreparingTorrent(false);
    setHandoff(result.report||result.failure?result:{complete:true,failure:'The torrent recovery returned no result.'});
   }
  }catch(e){if(active){setPreparingTorrent(false);setHandoff({complete:true,failure:String(e)})}}finally{polling=false}};
  void poll();const timer=setInterval(()=>void poll(),1000);return()=>{active=false;clearInterval(timer)};
 },[preparingTorrent,id]);
 const startRecoveryTorrent=async(candidate:number,file_index:number,info_hash:string)=>{
  setError('');setBusy(true);
  try{
   await invoke('file_operation',{id,operation:'start-recovery-torrent',value:JSON.stringify({candidate,file_index,info_hash,accept_partial_match:acceptTorrentRisk})});
   setHandoff(null);setPreparingTorrent(true);
  }catch(e){setHandoff({complete:true,failure:String(e)})}finally{setBusy(false)}
 };
 const run=async(action:string)=>{setBusy(true);setError('');try{await invoke('download_action',{action,ids:[id]});if(action==='pause'&&item?.status==='Downloading')setItem({...item,status:'Stopped',speed:0});}catch(e){setError(String(e))}finally{setBusy(false)}};
 const save=async()=>{setBusy(true);setError('');try{const n=Number(kb);if(limited&&(!Number.isInteger(n)||n<1||n>10_000_000))throw Error('Enter 1–10,000,000 KB/sec.');await invoke('file_operation',{id,operation:'speed-limit',value:limited?String(n):'off'});}catch(e){setError(String(e))}finally{setBusy(false)}};
 const server=visual?.server,torrent=visual?.torrent,isTorrent=Boolean(visual?.is_torrent),mixed=Boolean(visual?.direct_recovery);
 const ordinary=Boolean(visual&&!visual.is_torrent&&!visual.is_video&&!visual.is_gallery&&!visual.is_remote);
 const stage=visual?.recovery_stage;
 const recoveryPreparing=preparingTorrent||stage==='preparing';
 const recoverySearching=searching||stage==='searching';
 const handoffReport=handoff?.report;
 const recoveryBusy=busy||checking||repairing||recoverySearching||recoveryPreparing||Boolean(handoffReport&&!isTorrent);
 const matches=torrentSearch?.matches??[];
 const noCandidateChecks=Boolean(torrentSearch?.searched&&torrentSearch.failed===torrentSearch.searched);
 const torrentActive=item?.status==='Downloading';
 const sharing=item?.status==='Complete'&&Boolean(torrent?.upload_speed);
 const statusText=torrentActive
  ?isTorrent?(item.speed>0?'Receiving from peers…':'Connecting to peers…')
   :visual?.connections.some(c=>c.state==='Receiving')?'Receiving data…':'Connecting…'
  :sharing?'Sharing with peers':item?.status==='Stopped'?'Paused':item?.status??'Waiting…';
 const metadata=item?[
  ['Status',statusText],['Transfer method',!visual?'Unknown':mixed?'Direct download → BitTorrent':isTorrent?'BitTorrent':'Direct download'],
  ['File size',units(item.size)],['Downloaded',`${units(item.downloaded)} (${pct(item).toFixed(2)}%)`],
  ['Transfer rate',torrentActive?rate(item.speed):'—'],['Time left',timeLeft(item)],
  ['Resume capability',visual?.resumable===true?'Yes':visual?.resumable===false?'No':'Unknown'],
  ...(!isTorrent?[['Server',`${server?.place?.name??country(server?.country_code)}${server?.rtt_ms!=null?` · about ${server.rtt_ms} ms${server.place?.reach?` (${server.place.reach})`:""}`:''}`]]:[])
 ]:[];
 const showRecovery=ordinary&&!handoffReport&&item?.status!=='Downloading'&&item?.status!=='Complete';
 const recoveryStatus=(()=>{
  if(recoveryPreparing)return 'Torrent match selected. Rechecking saved pieces before continuing with BitTorrent peers…';
  if(recoverySearching){
   if(searchMethod==='magnet')return 'Connecting to peers to check the magnet metadata against saved pieces…';
   if(searchMethod==='url')return 'Fetching torrent metadata and checking it against saved pieces…';
   if(searchMethod==='torrent-file')return 'Checking the selected torrent against saved pieces…';
   if(searchMethod==='archive')return 'Searching Internet Archive for a matching torrent…';
   if(visual?.recovery_auto_search)return 'The direct download failed. Searching Internet Archive for a matching torrent…';
   return 'Checking torrent candidates against saved pieces…';
  }
  if(handoff?.failure||stage==='handoff-failed')return 'A torrent match was found, but the transfer could not switch. Review the match again or check another source below.';
  if(torrentSearch?.failure||noCandidateChecks||stage==='search-failed')return 'The torrent search or verification could not finish. Try another source below.';
  if(matches.length||stage==='matched')return 'A possible torrent match is ready for review below.';
  if(torrentSearch||stage==='no-match')return 'A matching torrent could not be verified. Try another source below.';
  return '';
 })();
 const cancel=async()=>{
  setError('');setBusy(true);
  try{
   if(!isTorrent&&(recoveryPreparing||handoffReport||handoffAvailable||(searchAvailable&&visual?.recovery_auto_search)||stage==='matched')){
    await invoke('file_operation',{id,operation:'cancel-recovery-torrent',value:null});
   }else if(torrentActive||mixed&&item?.status==='Queued'){
    await invoke('download_action',{action:'pause',ids:[id]});
   }
   await getCurrentWindow().close();
  }catch(e){setError(String(e))}finally{setBusy(false)}
 };
 const reusedBytes=handoffReport?.verified_bytes??visual?.recovery_verified_bytes;
 return <CrystalWindow target="details"><WindowTop title={`${item?pct(item).toFixed(0)+'% ':''}${item?.file??'Download'}`}/>
  <nav className="cg-page-tabs">{(['Download status','Speed Limiter','Options on completion'] as Tab[]).map(t=><button className={tab===t?'active':''} key={t} onClick={()=>setTab(t)}>{t}</button>)}</nav>
  <main ref={pageRef} className="cg-page cg-minimal-progress cg-piped-progress-page">
   {!item?<div className="cg-empty">Waiting for download information…</div>:tab==='Download status'?<>
    <section className="cg-glass cg-mdm-details">
     <div className="cg-download-url" title={item.url}>{mixed?'Original address: ':''}{item.url}</div>
     <dl>{metadata.map(([label,value])=><div key={label}><dt>{label}</dt><dd title={value}>{label==='Server'&&<CountryFlag place={server?.place}/>} {value}</dd></div>)}</dl>
    </section>
    {item.error&&<p className="cg-error" role="alert">{ordinary?'Direct download error: ':''}{item.error}</p>}
    {(mixed||handoffReport)&&<section className="cg-glass cg-progress-section cg-recovery-panel" aria-label="Direct download recovered by torrent">
     <h3>{!mixed?'Prepared for torrent recovery':torrentActive?'Downloading via BitTorrent':item.status==='Complete'?'Completed via BitTorrent':'Continued via BitTorrent'}</h3>
     <p>{mixed?'Auralis started this file as a direct download and switched to BitTorrent peers.':'Auralis is starting the transfer through BitTorrent peers.'} {reusedBytes!=null?`Reused ${units(reusedBytes)} of verified pieces.`:'Reused verified pieces from the direct download.'}</p>
     {visual?.recovery_direct_error&&<p><strong>Original direct download error</strong> {visual.recovery_direct_error}</p>}
     <p>The original partial was preserved{visual?.original_partial?` at ${visual.original_partial}`:''}. Recovery file: {handoffReport?.path??item.path}</p>
    </section>}
    <section className="cg-glass cg-progress-section cg-progress-tube cg-overall"><GradientBar percent={pct(item)} size={item.size} active={torrentActive} showLabel/></section>
    {showRecovery&&<section className="cg-glass cg-progress-section cg-recovery-panel" aria-labelledby="cg-recovery-heading">
     <h3 id="cg-recovery-heading">Torrent recovery</h3>
     {recoveryStatus&&<p role="status">{recoveryStatus}</p>}
     {torrentSearch?.failure&&<p role="alert" className="cg-error">{torrentSearch.failure}</p>}
     {handoff?.failure&&<p role="alert" className="cg-error">{handoff.failure}</p>}
     <details open={Boolean(recoveryStatus)||undefined}>
      <summary>Find a torrent for recovery</summary>
      <p>Searching sends words from this file’s name to Internet Archive. Checking a magnet connects to peers, and checking a torrent URL contacts its host. A match verifies only the pieces compared. Checking reads the saved data. The torrent transfer starts only after a match is selected. Continuing copies verified pieces into a new recovery folder, keeps the original partial and downloads the missing pieces from peers.</p>
      <div className="cg-bottom-actions">
       <button className="cg-btn" disabled={recoveryBusy} onClick={()=>void startTorrentSearch('archive')}>Search Internet Archive</button>
       <button className="cg-btn" disabled={recoveryBusy} onClick={()=>void startTorrentSearch('torrent-file')}>Choose torrent file…</button>
      </div>
      <form className="cg-recovery-link" onSubmit={e=>{e.preventDefault();void checkTorrentLink()}}>
       <label className="cg-field">Magnet or torrent URL<input value={torrentLink} maxLength={8192} onChange={e=>setTorrentLink(e.target.value)} placeholder="magnet:?xt=… or https://…/file.torrent"/></label>
       <button className="cg-btn" disabled={recoveryBusy||!torrentLink.trim()}>Check link</button>
      </form>
      {searchActionError&&<p role="alert" className="cg-error">{searchActionError}</p>}
      {torrentSearch&&!torrentSearch.failure&&<div aria-label="Torrent search results">
       <p>{matches.length?`${matches.length} possible file ${matches.length===1?'match':'matches'}.`:
        !torrentSearch.searched?'No candidates were returned.':
        noCandidateChecks?'No candidates could be checked.':'No saved pieces matched the checked candidates.'} Candidates found: {torrentSearch.searched??0}. Checks that failed: {torrentSearch.failed??0}.</p>
       {matches.length>0&&limit?.checksum&&<p>Torrent recovery is unavailable for a file with an expected whole-file checksum.</p>}
       {matches.length>0&&limit&&!limit.checksum&&<label className="cg-toggle">
        <span>I understand that continuing uses BitTorrent peers and the rest of the torrent may differ from the original file.</span>
        <input type="checkbox" checked={acceptTorrentRisk} disabled={recoveryBusy} onChange={e=>setAcceptTorrentRisk(e.target.checked)}/>
       </label>}
       <ul className="cg-recovery-matches">{matches.map(m=><li key={`${m.candidate}-${m.file_index}`}>
        <div><strong>{m.title}</strong><small>{m.path} · {m.matching_pieces} matching pieces · {m.unavailable_pieces} unchecked</small></div>
        <button className="cg-btn" disabled={!acceptTorrentRisk||recoveryBusy||!limit||Boolean(limit.checksum)} onClick={()=>void startRecoveryTorrent(m.candidate,m.file_index,m.info_hash)}>Continue with this torrent</button>
       </li>)}</ul>
      </div>}
     </details>
    </section>}
    {visual?.recovery_damaged&&!checkMessage&&<p role="alert" className="cg-error">Saved data was found changed. Resume is blocked to protect the partial file.</p>}
    {checkMessage&&<p role="status" className="cg-muted">{checkMessage}</p>}
    {checking&&<p role="status" className="cg-muted">Checking saved data…</p>}
    {repairing&&<p role="status" className="cg-muted">Checking the source and preparing damaged ranges…</p>}
    <div className="cg-indicator-row">
     {isTorrent?<section className="cg-glass cg-progress-section cg-swarm">
      <div className="cg-section-title"><h3><Network size={15} aria-hidden="true"/> BitTorrent swarm</h3></div>
      <dl>
       <dt>Connected peers</dt><dd>{torrent?.peers??'—'}</dd>
       <dt>Upload speed</dt><dd>{torrent?rate(torrent.upload_speed):'—'}</dd>
       <dt>Uploaded</dt><dd>{torrent?units(torrent.uploaded):'—'}</dd>
       <dt>Selected files</dt><dd>{torrent?torrent.selected_files??'All':'—'}</dd>
       {torrent?.info_hash&&<><dt>Info hash</dt><dd title={torrent.info_hash}>{torrent.info_hash}</dd></>}
      </dl>
     </section>:<section className="cg-glass cg-progress-section cg-selected-chunks">
      <div className="cg-section-title"><h3>Connections</h3></div>
      <ConnectionMap segments={visual?.segments} connections={visual?.connections} downloading={torrentActive} paused={item.status==="Stopped"} tubes/>
     </section>}
     <section className="cg-glass cg-progress-section cg-progress-combined cg-progress-graph"><div className="cg-compact-speed"><div className="cg-section-title"><h3>Transfer speed</h3><small>{rate(item.speed)} · last {Math.round(values.length*1.2)} sec</small></div><SpeedGraph values={values}/></div></section>
    </div>
   </>:tab==='Speed Limiter'?<section className="cg-glass cg-progress-section"><h3>Speed Limiter</h3><label className="cg-toggle"><span><strong>Use Speed Limiter</strong><small>Remember the limit after pause and resume</small></span><input type="checkbox" checked={limited} disabled={!limit||busy} onChange={e=>setLimited(e.target.checked)}/></label><label className="cg-field">Maximum speed (KB/sec)<input type="number" min="1" value={kb} disabled={!limited||busy} onChange={e=>setKb(e.target.value)}/></label><button className="cg-btn cg-btn-primary" disabled={!limit||busy} onClick={()=>void save()}><Save size={16}/>Apply limit</button></section>:<CrystalCompletionOptions id={id}/>}
   <TubeBridge container={pageRef} ready={!!item&&!isTorrent&&tab==='Download status'} active={receivingTubeSlots(visual?.connections,item?.status==='Downloading').some(Boolean)} colors={indicatorColors(appearance.connectionIndicator)} progressColors={indicatorColors(appearance.indicator)}/>
   {error&&<p className="cg-error" role="alert">{error}</p>}
   <div className="cg-bottom-actions">
    {showRecovery&&<button className="cg-btn" disabled={recoveryBusy} onClick={()=>void checkSaved()}>Check saved data</button>}
    {showRecovery&&(damaged||visual?.recovery_damaged)&&<button className="cg-btn" disabled={recoveryBusy} onClick={()=>void repairSaved()}>Check source and repair</button>}
    <button className="cg-btn cg-neon-violet" onClick={()=>openWindow(`properties-${id}`,`/?properties=${id}`,760,600)}><FileText size={15}/>Properties</button>
    <span className="cg-action-space"/>
    {torrentActive?<button className="cg-btn cg-neon-amber" disabled={busy} onClick={()=>void run('pause')}><Pause size={16}/>Pause</button>
    :item&&item.status!=='Complete'?<button className="cg-btn cg-neon-mint" disabled={recoveryBusy||damaged||Boolean(visual?.recovery_damaged)} onClick={()=>void run('start')}><Play size={16}/>Resume</button>:null}
    <button className="cg-btn cg-btn-danger" disabled={busy} onClick={()=>void cancel()}>Cancel</button>
   </div>
  </main></CrystalWindow>;
}
