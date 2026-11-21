import { invoke } from '@tauri-apps/api/core';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { useEffect, useRef, useState } from 'react';
import { Power, X } from 'lucide-react';
import { CrystalWindow, WindowTop } from './CrystalShared';
type State={id:number;pending:{mode:string;seconds:number;force:boolean}|null};
export default function CrystalPower({id}:{id:number}){
 const [state,setState]=useState<State|null>(null),[error,setError]=useState('');const performing=useRef(false);
 const action=async(action:string)=>{if(performing.current)return;performing.current=true;try{await invoke('glass_tool',{action:'power',payload:{id,action}});await getCurrentWindow().close()}catch(e){performing.current=false;setError(String(e))}};
 useEffect(()=>{let active=true;const poll=async()=>{try{const next=await invoke<State>('glass_tool',{action:'power-state',payload:null});if(!active)return;if(next.id!==id||!next.pending){await getCurrentWindow().close();return;}setState(next);if(next.pending.seconds===0)await action('execute')}catch(e){if(active)setError(String(e))}};void poll();const timer=setInterval(()=>void poll(),500);return()=>{active=false;clearInterval(timer)}},[id]);
 const verb=state?.pending?.mode==='Sleep'?'go to sleep':state?.pending?.mode==='Hibernate'?'hibernate':'shut down';
 return <CrystalWindow target="details"><WindowTop noMax title="Download completion"/><main className="cg-page cg-tool-body"><h2><Power size={20}/>Downloads finished</h2><p>The computer will {verb} in <strong>{state?.pending?.seconds??30} seconds</strong>.</p>{state?.pending?.force&&<p className="cg-error">Applications will be forced to close. Unsaved work may be lost.</p>}{error&&<p className="cg-error">{error}</p>}<div className="cg-bottom-actions" style={{marginTop:'auto'}}><button className="cg-btn cg-btn-danger" onClick={()=>void action('execute')}><Power size={15}/>Continue now</button><span className="cg-action-space"/><button autoFocus className="cg-btn cg-btn-primary" onClick={()=>void action('cancel')}><X size={15}/>Cancel</button></div></main></CrystalWindow>;
}
