import { invoke } from '@tauri-apps/api/core';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { useEffect, useRef, useState } from 'react';
import { CheckCheck, ExternalLink, FileArchive, FolderOpen, Move, Plus, X } from 'lucide-react';
import { CrystalWindow, WindowTop, units, openWindow } from './CrystalShared';
import type { Dashboard, Download } from './CrystalShared';

const close=()=>getCurrentWindow().close();
type Pending={categories?:Dashboard['categories'];id:number;waiting:number;info:null|{url:string;save_as:string;category:string;description:string;remember:boolean;size:number|null;probing:boolean;error:string|null;server:{country_code:string|null;rtt_ms:number|null}}};
export function CrystalFileInfo({id}:{id:number}){
 const [pending,setPending]=useState<Pending|null>(null),[categories,setCategories]=useState<Dashboard['categories']>([]);
 const [form,setForm]=useState({save_as:'',description:'',remember:false,chunks:8});
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 const initialized=useRef(false),pathEdited=useRef(false);
 useEffect(()=>{
  let active=true,running=false;
  const load=async()=>{if(running)return;running=true;try{
   const next=await invoke<Pending>('pending_file_info');if(!active)return;
   if(next.id!==id||!next.info){void close();return;}
   setPending(next);if(next.categories)setCategories(next.categories);const info=next.info;
   setForm(old=>initialized.current?{...old,...(!pathEdited.current?{save_as:info.save_as}:{})}:{...old,save_as:info.save_as,description:info.description,remember:info.remember});
   initialized.current=true;
  }catch(e){if(active)setError(String(e))}finally{running=false}};
  void load();const timer=setInterval(()=>void load(),750);
  void invoke<Dashboard>('dashboard_snapshot').then(d=>{if(active)setCategories(d.categories)}).catch(e=>{if(active)setError(String(e))});
  void invoke<{max_connections:number}>('glass_settings').then(c=>{if(active)setForm(old=>({...old,chunks:c.max_connections}))}).catch(()=>undefined);
  return()=>{active=false;clearInterval(timer)};
 },[id]);
 const perform=async(action:string,payload:unknown=null)=>invoke<{id?:number}>('file_info_action',{id,action,payload});
 const start=async(later:boolean)=>{setBusy(true);setError('');try{await perform('commit',{...form,later});await close()}catch(e){setError(String(e));setBusy(false)}};
 const info=pending?.info;
 return <CrystalWindow target="details"><WindowTop noMax title="Download File Info"/>
  <main className="cg-page cg-file-info">
   <label className="cg-field">URL<input value={info?.url??''} readOnly title={info?.url}/></label>
   <div className="cg-info-layout"><div>
    <label className="cg-field">Category<div className="cg-input-row"><select value={info?.category??''} disabled={busy||!info} onChange={async e=>{setError('');pathEdited.current=false;try{await perform('category',{category:e.target.value})}catch(x){setError(String(x))}}>
     {categories.map(c=><option value={c.key} key={c.key}>{c.name}</option>)}</select>
     <button className="cg-btn cg-neon-violet" title="Add category" onClick={()=>openWindow('tool-category','/?tool=category',640,480)}><Plus size={16}/></button></div></label>
    <label className="cg-field">Save As<div className="cg-input-row"><input value={form.save_as} onChange={e=>{pathEdited.current=true;setForm(old=>({...old,save_as:e.target.value}))}}/>
     <button className="cg-btn" title="Choose save location" onClick={async()=>{try{const path=await invoke<string|null>('choose_download_path',{current:form.save_as});if(path){pathEdited.current=true;setForm(old=>({...old,save_as:path}))}}catch(e){setError(String(e))}}><FolderOpen size={16}/></button></div></label>
    <div className="cg-remember-path"><label><input type="checkbox" checked={form.remember} onChange={e=>setForm(old=>({...old,remember:e.target.checked}))}/> Remember this path for “{categories.find(c=>c.key===info?.category)?.name??info?.category}” category</label>
     <input readOnly disabled={!form.remember} aria-label="Remembered folder" value={form.save_as.replace(/[\\/][^\\/]*$/,'')}/></div>
   </div><div className="cg-info-file"><FileArchive size={36}/><strong>{units(info?.size)}</strong><small>{info?.probing?'Checking file…':'Archive / file'}</small><button className="cg-btn" disabled title="Preview is available after a transfer has created a previewable file">Preview</button></div></div>
   <label className="cg-field">Description<input value={form.description} onChange={e=>setForm(old=>({...old,description:e.target.value}))}/></label>
   <div className="cg-info-bottom"><span className="cg-muted">Server　{info?.server.country_code??'Not yet observed'}{info?.server.rtt_ms!=null?` · ${info.server.rtt_ms} ms`:''}</span>
    <label className="cg-inline-field">Chunks / connections<select value={form.chunks} onChange={e=>setForm(old=>({...old,chunks:Number(e.target.value)}))}>{[1,2,4,8,16,32,64,128].includes(form.chunks)?null:<option>{form.chunks}</option>}{[1,2,4,8,16,32,64,128].map(n=><option key={n} value={n}>{n}</option>)}</select></label></div>
   {error&&<p className="cg-error" role="alert">{error}</p>}
   {info?.error&&<p className="cg-error">{info.error}</p>}
   <div className="cg-bottom-actions"><button className="cg-btn cg-neon-violet" disabled={busy||!info} onClick={()=>void start(true)}>Download Later</button><span className="cg-action-space"/><button className="cg-btn cg-btn-primary" disabled={busy||!info||!form.save_as} onClick={()=>void start(false)}>Start Download</button><button className="cg-btn" disabled={busy} onClick={async()=>{try{await perform('cancel');await close()}catch(e){setError(String(e))}}}>Cancel</button></div>
  </main></CrystalWindow>;
}

export function CrystalComplete({id}:{id:number}){
 const [item,setItem]=useState<Download|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false),[dont,setDont]=useState(false);
 useEffect(()=>{void invoke<Dashboard>('dashboard_snapshot').then(d=>setItem(d.downloads.find(x=>x.id===id)??null)).catch(e=>setError(String(e)))},[id]);
 const open=async(operation:string)=>{setBusy(true);setError('');try{await invoke('file_operation',{id,operation,value:null})}catch(e){setError(String(e))}finally{setBusy(false)}};
 return <CrystalWindow target="details"><WindowTop noMax title="Download complete"/>
  <main className="cg-page cg-complete-page"><div className="cg-complete-heading"><CheckCheck size={34}/><div><h2>Download complete</h2><p>Downloaded {units(item?.downloaded)} ({item?.downloaded.toLocaleString()??'—'} bytes)</p></div></div>
   <label className="cg-field">Address<input value={item?.url??''} readOnly title={item?.url}/></label>
   <label className="cg-field">The file saved as<input value={item?.path??''} readOnly title={item?.path}/></label>
   <div className="cg-complete-buttons"><button className="cg-btn cg-btn-primary" disabled={busy||!item} onClick={()=>void open('open')}><ExternalLink size={16}/>Open</button><button className="cg-btn cg-neon-violet" disabled={busy||!item} onClick={()=>void open('open-with')}>Open with…</button><button className="cg-btn cg-neon-amber" disabled={busy||!item} onClick={()=>void open('folder')}><FolderOpen size={16}/>Open folder</button><button className="cg-btn" onClick={()=>void close()}><X size={16}/>Close</button></div>
   <div className="cg-complete-footer"><label><input type="checkbox" checked={dont} onChange={async e=>{const on=e.target.checked;setError('');try{await invoke('update_glass_setting',{key:'show_complete',value:String(!on)});setDont(on)}catch(e){setError(String(e))}}}/>Don’t show this dialog again</label><button className="cg-btn cg-drag-file" title="Drag the file into a folder or an app" disabled={!item} onMouseDown={e=>{if(e.button===0){e.preventDefault();void invoke('drag_download',{id}).catch(x=>setError(String(x)))}}}><Move size={18}/>Drag file</button></div>
   {error&&<p className="cg-error" role="alert">{error}</p>}
  </main></CrystalWindow>;
}
