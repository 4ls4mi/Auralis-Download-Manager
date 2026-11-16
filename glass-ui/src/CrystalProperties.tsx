import { invoke } from "@tauri-apps/api/core";
import { useEffect, useState } from "react";
import { File, FolderOpen, HardDrive, Pause, Play, RefreshCw } from "lucide-react";
import { CrystalWindow, WindowTop, GradientBar, pct, units, rate } from "./CrystalShared";
import type { Dashboard, Download } from "./CrystalShared";

export default function CrystalProperties({ id }: { id: number }) {
  const [item,setItem]=useState<Download|null>(null),[error,setError]=useState("");
  const [busy,setBusy]=useState(false);
  const load=async()=>{
    try{
      const snapshot=await invoke<Dashboard>("dashboard_snapshot");
      setItem(snapshot.downloads.find(x=>x.id===id)??null);
    }catch(e){setError(String(e))}
  };
  useEffect(()=>{void load()},[id]);
  const open=async(operation:"open"|"folder")=>{
    setBusy(true);setError("");
    try{await invoke("file_operation",{id,operation,value:null})}
    catch(e){setError(String(e))}finally{setBusy(false)}
  };
  const run=async(action:"start"|"pause")=>{
    setBusy(true);setError("");
    try{await invoke("download_action",{action,ids:[id]});await load()}
    catch(e){setError(String(e))}finally{setBusy(false)}
  };
  return <CrystalWindow target="details"><WindowTop title="File Properties — Mister Hybrid Glass"/>
    <main className="cg-page" style={{display:"flex",flexDirection:"column",gap:13}}>
      {item?<><header className="cg-progress-summary cg-glass"><File size={30} color="var(--accent)"/>
        <div style={{minWidth:0,flex:1}}><h2>{item.file}</h2><p>{item.status} • {item.category}</p></div></header>
        <section className="cg-glass cg-progress-section">
          <div className="cg-section-title"><h3>File details</h3><small>{pct(item).toFixed(1)}% complete</small></div>
          <GradientBar percent={pct(item)} showLabel/>
          <div style={{display:"grid",gridTemplateColumns:"110px minmax(0,1fr)",gap:10,marginTop:17,fontSize:11,lineHeight:1.7}}>
            <span className="cg-muted">File size</span><span>{units(item.size)}</span>
            <span className="cg-muted">Downloaded</span><span>{units(item.downloaded)}</span>
            <span className="cg-muted">Transfer rate</span><span>{rate(item.speed)}</span>
            <span className="cg-muted">Download URL</span><span style={{overflowWrap:"anywhere"}}>{item.url}</span>
            <span className="cg-muted">Saved at</span><span style={{overflowWrap:"anywhere"}}>{item.path}</span>
          </div>
        </section>
        <div className="cg-bottom-actions" style={{marginTop:"auto"}}>
          <button className="cg-btn" disabled={busy} onClick={()=>void open("folder")}><FolderOpen size={16}/> Open Folder</button>
          <button className="cg-btn" disabled={busy||item.status!=="Complete"} onClick={()=>void open("open")}><HardDrive size={16}/> Open</button>
          {item.status==="Downloading"?
            <button className="cg-btn cg-btn-primary" disabled={busy} onClick={()=>void run("pause")}><Pause size={16}/> Stop</button>:
            item.status!=="Complete"?<button className="cg-btn cg-btn-primary" disabled={busy} onClick={()=>void run("start")}><Play size={16}/> Resume</button>:null}
          <button className="cg-btn" onClick={()=>void load()}><RefreshCw size={15}/> Refresh</button>
        </div></>:<div className="cg-empty"><File size={28}/><strong>File not found</strong></div>}
      {error&&<p className="cg-error">{error}</p>}
    </main>
  </CrystalWindow>;
}
