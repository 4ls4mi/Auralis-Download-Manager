import { useEffect, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { Trash2 } from 'lucide-react';
import { CrystalWindow, WindowTop } from './CrystalShared';
export type DeleteRequest={ids:number[];name:string;disk:boolean;dontAsk:boolean};
export default function CrystalDelete(){
 const [request,setRequest]=useState<DeleteRequest|null>(()=>{try{return JSON.parse(localStorage.getItem('glass-delete-request')??'null')}catch{return null}});
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 useEffect(()=>{const receive=(event:StorageEvent)=>{if(event.key==='glass-delete-request'&&event.newValue){try{setRequest(JSON.parse(event.newValue));setError('')}catch{setError('The deletion request could not be read.')}}};window.addEventListener('storage',receive);return()=>window.removeEventListener('storage',receive)},[]);
 const close=()=>getCurrentWindow().close();
 const remove=async()=>{if(!request)return;setBusy(true);setError('');try{
  for(let n=0;n<request.ids.length;n+=100){const result=await invoke<{skipped:{why:string}[]}>('download_action',{action:request.disk?'delete':'remove',ids:request.ids.slice(n,n+100)});if(result.skipped.length)throw Error(result.skipped.map(x=>x.why).join('; '))}
  await invoke('glass_tool',{action:'original-setting',payload:{key:'delete_files_too',value:request.disk}});
  if(request.dontAsk)await invoke('update_glass_setting',{key:'confirm_delete',value:'false'});
  localStorage.removeItem('glass-delete-request');await close();
 }catch(e){setError(String(e));setBusy(false)}};
 return <CrystalWindow target="details"><WindowTop noMax title="Confirm deletion of downloads"/><main className="cg-page cg-tool-body" role="dialog" aria-label="Confirm deletion of downloads"><h2><Trash2 size={20}/> Delete download?</h2><p>Are you sure you want to delete “{request?.name}” from the list of downloads?</p><label><input type="checkbox" checked={request?.disk??false} disabled={busy} onChange={e=>request&&setRequest({...request,disk:e.target.checked})}/> Also delete the file from disk</label><label><input type="checkbox" checked={request?.dontAsk??false} disabled={busy} onChange={e=>request&&setRequest({...request,dontAsk:e.target.checked})}/> Don’t show this dialog again</label>{error&&<p className="cg-error">{error}</p>}<div className="cg-bottom-actions" style={{marginTop:'auto'}}><span className="cg-action-space"/><button className="cg-btn cg-btn-danger" disabled={busy||!request} onClick={()=>void remove()}>Yes</button><button className="cg-btn cg-btn-primary" disabled={busy} onClick={()=>void close()}>No</button></div></main></CrystalWindow>;
}
