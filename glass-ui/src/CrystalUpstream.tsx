import {useCallback,useEffect,useState} from 'react';
import {invoke} from '@tauri-apps/api/core';
type Status={state:string;version?:string;date?:string;message?:string};
export default function CrystalUpstream(){
 const [status,setStatus]=useState<Status>({state:'not-checked'}),[error,setError]=useState('');
 const load=useCallback(async()=>{try{setStatus(await invoke<Status>('glass_tool',{action:'upstream-status',payload:null}));setError('')}catch(e){setError(String(e))}},[]);
 useEffect(()=>{void load();const timer=setInterval(()=>void load(),3000);return()=>clearInterval(timer)},[load]);
 const label=status.state==='checking'?'Checking the original MDM release…':status.state==='newer'?`Original MDM ${status.version} is available (${status.date}).`:status.state==='latest'?'The original MDM release is not newer than this backend.':status.state==='error'?`Update check failed: ${status.message}`:'No release check yet.';
 return <section className="cg-glass cg-progress-section"><h3>Original MDM releases</h3><p role="status">{label}</p><p>Glass keeps its own interface and installation. Original app releases are reviewed before their changes are integrated.</p><div className="cg-bottom-actions"><button className="cg-btn cg-neon-violet" disabled={status.state==='checking'} onClick={async()=>{try{await invoke('glass_tool',{action:'upstream-check',payload:null});await load()}catch(e){setError(String(e))}}}>Check for updates</button><button className="cg-btn" onClick={()=>void invoke('open_upstream_releases').catch(e=>setError(String(e)))}>Release notes</button></div>{error&&<p className="cg-error" role="alert">{error}</p>}</section>
}
