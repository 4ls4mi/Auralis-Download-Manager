import {useEffect,useState} from 'react';
import {invoke} from '@tauri-apps/api/core';
import {getCurrentWindow} from '@tauri-apps/api/window';
import {CrystalWindow,WindowTop} from './CrystalShared';
type Request={action:'redownload'|'exit';id?:number;name?:string};
export default function CrystalConfirm(){
 const [request,setRequest]=useState<Request|null>(()=>{try{return JSON.parse(localStorage.getItem('glass-confirm-request')??'null')}catch{return null}});
 const [error,setError]=useState(''),[busy,setBusy]=useState(false);
 useEffect(()=>{const listener=(e:StorageEvent)=>{if(e.key==='glass-confirm-request'&&e.newValue){try{setRequest(JSON.parse(e.newValue));setError('')}catch{setError('Could not read the request.')}}};window.addEventListener('storage',listener);return()=>window.removeEventListener('storage',listener)},[]);
 const close=()=>getCurrentWindow().close();
 const confirm=async()=>{if(!request)return;setBusy(true);setError('');try{if(request.action==='exit'){await invoke('quit_glass');return}await invoke('file_operation',{id:request.id,operation:'redownload',value:null});localStorage.setItem('glass-downloads-changed',String(Date.now()));await close()}catch(e){setError(String(e));setBusy(false)}};
 return <CrystalWindow target="details"><WindowTop noMax title={request?.action==='exit'?'Exit Mister Hybrid Glass':'Confirm redownload'}/><main className="cg-page cg-tool-body" role="dialog" aria-label={request?.action==='exit'?'Confirm exit':'Confirm redownload'}><h2>{request?.action==='exit'?'Exit the app?':'Redownload this file?'}</h2><p>{request?.action==='exit'?'Active downloads will stop and their progress will be saved.':`Redownload “${request?.name??''}” from the beginning?`}</p>{error&&<p role="alert" className="cg-error">{error}</p>}<div className="cg-bottom-actions" style={{marginTop:'auto'}}><span className="cg-action-space"/><button className="cg-btn cg-btn-danger" disabled={busy||!request} onClick={()=>void confirm()}>Yes</button><button className="cg-btn cg-btn-primary" disabled={busy} onClick={()=>void close()}>Cancel</button></div></main></CrystalWindow>
}
