import {useEffect, useState} from 'react';
import {listen} from '@tauri-apps/api/event';
import {units} from './CrystalShared';
export type UpdateProgress={phase:'downloading'|'verifying';downloaded:number;total:number};
export function useUpdateProgress(){
 const [progress,setProgress]=useState<UpdateProgress|null>(null);
 useEffect(()=>{let closed=false,unlisten:(()=>void)|undefined;void listen<UpdateProgress>('auralis-update-progress',event=>{if(!closed)setProgress(event.payload)}).then(stop=>{if(closed)stop();else unlisten=stop}).catch(()=>undefined);return()=>{closed=true;unlisten?.()}},[]);
 return [progress,setProgress] as const;
}
export function UpdateProgressView({progress,installing}:{progress:UpdateProgress|null;installing:boolean}){
 const total=progress?.total??0,downloaded=Math.min(total,Math.max(0,progress?.downloaded??0));
 const pct=total>0?Math.round(downloaded/total*100):0;
 const label=installing?'Starting installer…':progress?.phase==='verifying'?'Verifying downloaded update…':progress?'Downloading update…':'Preparing download…';
 return <div className="cg-update-progress" role="status" aria-live="polite"><strong>{label}</strong>{progress&&<><progress aria-label="Update download progress" max={100} value={pct}/><small>{units(downloaded)} / {units(total)} · {pct}%</small></>}</div>;
}
