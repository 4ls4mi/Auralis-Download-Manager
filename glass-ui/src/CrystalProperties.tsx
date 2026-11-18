import { invoke } from '@tauri-apps/api/core';
import { useEffect, useState } from 'react';
import { File, FolderOpen, HardDrive, RefreshCw } from 'lucide-react';
import { CrystalWindow, WindowTop, units, rate, pct, openWindow } from './CrystalShared';
import type { Dashboard, Download, DownloadVisual, VisualDashboard } from './CrystalShared';
export default function CrystalProperties({id}:{id:number}){
 const [item,setItem]=useState<Download|null>(null),[visual,setVisual]=useState<DownloadVisual|null>(null),[error,setError]=useState('');
 const load=async()=>{try{const [d,v]=await Promise.all([invoke<Dashboard>('dashboard_snapshot'),invoke<VisualDashboard>('dashboard_visuals')]);setItem(d.downloads.find(d=>d.id===id)??null);setVisual(v.downloads.find(d=>d.id===id)??null)}catch(e){setError(String(e))}};
 useEffect(()=>{void load()},[id]);
 const server=visual?.server;
 const fields=item?[
 ['File name',item.file],['Category',item.category],['File size',units(item.size)],['Downloaded',`${units(item.downloaded)} (${pct(item).toFixed(2)}%)`],['Status',item.status],['Transfer rate',rate(item.speed)],['Resume capability',visual?.resumable===true?'Yes':visual?.resumable===false?'No':'Unknown'],['Maximum connections',String(visual?.chunk_count??'Unavailable')],['Server hostname',server?.hostname],['Server IP',server?.ip],['Country',server?.place?.name??server?.country_code],['Connection RTT',server?.rtt_ms!=null?`${server.rtt_ms} ms`:null],['CDN',server?.cdn],['Proxy',server?.proxied?'Yes':'Not detected'],['Added',visual?.added??item.added],['Last attempt',visual?.last_try],['Description',visual?.description],['Referrer',visual?.referer],['Source page',visual?.page],['Download URL',item.url],['Saved at',item.path],['Error',item.error]
 ]:[];
 const open=async(operation:string)=>{setError('');try{await invoke('file_operation',{id,operation,value:null})}catch(e){setError(String(e))}};
 return <CrystalWindow target="details"><WindowTop title="File Properties"/><main className="cg-page cg-properties-page"><header className="cg-property-heading"><File size={24}/><h2>{item?.file??'File properties'}</h2></header><dl className="cg-property-grid">{fields.map(([label,value])=><div key={label}><dt>{label}</dt><dd title={value??undefined}>{value||'Unavailable'}</dd></div>)}</dl>{error&&<p className="cg-error">{error}</p>}<div className="cg-bottom-actions"><button className="cg-btn" disabled={!item} onClick={()=>void open('folder')}><FolderOpen size={15}/>Open folder</button><button className="cg-btn cg-neon-violet" disabled={item?.status!=='Complete'} onClick={()=>void open('open-with')}>Open with…</button><button className="cg-btn cg-btn-primary" disabled={item?.status!=='Complete'} onClick={()=>void open('open')}><HardDrive size={15}/>Open</button><button className="cg-btn" onClick={()=>void load()}><RefreshCw size={15}/>Refresh</button><button className="cg-btn" disabled={!item} onClick={()=>openWindow(`download-${id}`,`/?detail=${id}`,800,400)}>Download status</button></div></main></CrystalWindow>;
}
