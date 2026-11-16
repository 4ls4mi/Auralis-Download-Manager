import { invoke } from '@tauri-apps/api/core';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { useEffect, useState } from 'react';
import { Check, FolderOpen, Save } from 'lucide-react';
import { CrystalWindow, WindowTop } from './CrystalShared';
const names:Record<string,string>={category:'Add category',checksum:'Verify checksum',extract:'Extract archive','refresh-address':'Refresh download address'};
export default function CrystalTool({kind,id}:{kind:string;id:number}){
 const [value,setValue]=useState(''),[name,setName]=useState(''),[types,setTypes]=useState(''),[folder,setFolder]=useState(''),[password,setPassword]=useState('');
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState(''),[watch,setWatch]=useState(false),[askPassword,setAskPassword]=useState(false),[needsTool,setNeedsTool]=useState(false);
 useEffect(()=>{if(id)void invoke<{file:string;url:string;checksum?:string}>('file_operation',{id,operation:'details',value:null}).then(d=>{setName(d.file);setValue(kind==='refresh-address'?d.url:d.checksum??'')}).catch(e=>setError(String(e)))},[kind,id]);
 const operation=(operation:string,value:string|null=null)=>invoke<Record<string,unknown>>('file_operation',{id,operation,value});
 useEffect(()=>{
  if(!watch)return;let active=true,running=false;
  const poll=async()=>{if(running)return;running=true;try{const status=await operation(kind==='checksum'?'checksum-result':'extract-status');if(!active)return;
   if(kind==='checksum'){if(status.complete){setWatch(false);setMessage(status.matches?'The file matches the expected checksum.':'The file does not match the expected checksum.');if(!status.matches)setError('Checksum mismatch.')}}
   else {setAskPassword(Boolean(status.password_required));setNeedsTool(Boolean(status.needs_7zip));setMessage(String(status.message??(status.running?'Extracting…':'Waiting…')));}
  }catch(e){if(active){setWatch(false);setError(String(e))}}finally{running=false}};
  void poll();const timer=setInterval(()=>void poll(),900);return()=>{active=false;clearInterval(timer)};
 },[watch,kind,id]);
 const run=async()=>{setBusy(true);setError('');setMessage('');try{
  if(kind==='category'){if(!name.trim())throw Error('Enter a category name.');await invoke('glass_tool',{action:'category',payload:{name:name.trim(),types,folder}});await getCurrentWindow().close();}
  else if(kind==='checksum'){const r=await operation('checksum',value);setWatch(Boolean(r.pending));setMessage(r.pending?'Checking file…':String(r.message??'Checksum saved.'));}
  else if(kind==='extract'){await operation('extract');setWatch(true);setMessage('Extraction queued.');}
  else if(kind==='refresh-address'){await operation('refresh-address',value);setMessage('Download address updated. Existing resume data is preserved.');}
 }catch(e){setError(String(e))}finally{setBusy(false)}};
 return <CrystalWindow target="details"><WindowTop noMax title={names[kind]??'Download tool'}/><main className="cg-page cg-tool-body"><h2>{names[kind]??'Download tool'}</h2>{id>0&&<p className="cg-muted">{name}</p>}
  {kind==='category'?<><label className="cg-field">Name<input value={name} onChange={e=>setName(e.target.value)}/></label><label className="cg-field">File types<input placeholder="ZIP 7Z RAR" value={types} onChange={e=>setTypes(e.target.value)}/></label><label className="cg-field">Folder<div className="cg-input-row"><input value={folder} onChange={e=>setFolder(e.target.value)} placeholder="Use the default category folder"/><button className="cg-btn" onClick={async()=>{try{const path=await invoke<string|null>('choose_folder');if(path)setFolder(path)}catch(e){setError(String(e))}}}><FolderOpen size={16}/></button></div></label></>:kind==='extract'?<><p className="cg-muted">Extract this archive with MDM. Existing archive and password handling are preserved.</p>{askPassword&&<label className="cg-field">Archive password<div className="cg-input-row"><input type="password" autoComplete="off" value={password} onChange={e=>setPassword(e.target.value)}/><button className="cg-btn cg-btn-primary" disabled={busy} onClick={async()=>{setBusy(true);try{await operation('extract-password',password);setPassword('');setAskPassword(false)}catch(e){setError(String(e))}finally{setBusy(false)}}}>Continue</button></div></label>}{needsTool&&<p className="cg-error">Install 7-Zip for RAR and 7z archives, then retry extraction.</p>}</>:<label className="cg-field">{kind==='checksum'?'Expected checksum (MD5, SHA-1, SHA-256, SHA-512 or CRC32)':'New download URL'}<input value={value} onChange={e=>setValue(e.target.value)}/></label>}
  {message&&<p className={error?'cg-muted':'cg-success'}><Check size={14}/>{message}</p>}{error&&<p className="cg-error" role="alert">{error}</p>}
  <div className="cg-bottom-actions" style={{marginTop:'auto'}}><button className="cg-btn" onClick={()=>void getCurrentWindow().close()}>Close</button><span className="cg-action-space"/><button className="cg-btn cg-btn-primary" disabled={busy||kind==='checksum'&&watch} onClick={()=>void run()}><Save size={15}/>{kind==='checksum'?'Verify':kind==='extract'?'Extract':'Save'}</button></div>
 </main></CrystalWindow>;
}
