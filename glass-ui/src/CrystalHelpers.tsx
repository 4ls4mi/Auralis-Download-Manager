import {useCallback,useEffect,useRef,useState} from 'react';
import {invoke} from '@tauri-apps/api/core';
import {getCurrentWindow} from '@tauri-apps/api/window';
import {Download,RefreshCw} from 'lucide-react';
type Tools={tools:{name:string;version:string|null;path:string|null}[];job:{name:string;state:string}|null};
export default function CrystalHelpers(){
 const [data,setData]=useState<Tools|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const installedByUser=useRef(false);
 const load=useCallback(async()=>{try{setData(await invoke<Tools>('glass_tool',{action:'helpers',payload:null}));setError('')}catch(e){setError(String(e))}},[]);
 useEffect(()=>{void load();const timer=setInterval(()=>void load(),2000);return()=>clearInterval(timer)},[load]);
 useEffect(()=>{if(installedByUser.current&&new URLSearchParams(location.search).get('tool')==='helpers'&&data?.tools.some(t=>t.name.toLowerCase().includes('yt-dlp')&&t.version)&&data.job?.name==='yt-dlp'&&data.job.state==='ready'){const t=setTimeout(()=>void getCurrentWindow().close(),1800);return()=>clearTimeout(t)}},[data]);
 const install=async(name:string)=>{setBusy(true);setError('');try{await invoke('glass_tool',{action:'helpers-install',payload:{name}});if(name.toLowerCase().includes('yt-dlp'))installedByUser.current=true;await load()}catch(e){setError(String(e))}finally{setBusy(false)}};
 return <section className="cg-glass cg-progress-section"><h3>Video and gallery helpers</h3><p>Install or update the original MDM helpers. Existing installations are detected automatically.</p>{data?.tools.map(tool=><div className="cg-helper-row" key={tool.name}><div><strong>{tool.name}</strong><small>{tool.version?`${tool.version} · ${tool.path}`:'Not installed'}</small></div><button className="cg-btn cg-neon-violet" disabled={busy||data.job?.state==='installing'} onClick={()=>void install(tool.name)}>{tool.version?<RefreshCw size={15}/>:<Download size={15}/>} {tool.version?'Check / update':'Install'}</button></div>)}{data?.job&&<p role="status">{data.job.name}: {data.job.state}</p>}{error&&<p className="cg-error" role="alert">{error}</p>}</section>
}
