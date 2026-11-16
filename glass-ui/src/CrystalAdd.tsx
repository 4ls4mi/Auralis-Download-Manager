import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useState } from "react";
import { Download, FileArchive, Link2, Plus, X } from "lucide-react";
import { CrystalWindow, WindowTop } from "./CrystalShared";

export default function CrystalAdd({ mode }: { mode:"url"|"torrent" }) {
  const [url,setUrl]=useState(""),[later,setLater]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(""),[done,setDone]=useState("");
  const save=async()=>{
    if(!url.trim()){setError("Enter a download URL or magnet link.");return}
    setBusy(true);setError("");
    try{
      const result=await invoke<string>("add_download",{url:url.trim(),later});
      const parsed=JSON.parse(result) as {id?:number;pending?:boolean;error?:string};
      if(parsed.error)throw Error(parsed.error);
      setDone(parsed.pending?"Torrent metadata lookup started.":`Download ${parsed.id?"#"+parsed.id:""} added successfully.`);
      setUrl("");
    }catch(e){setError(String(e))}finally{setBusy(false)}
  };
  const pickFile=async()=>{
    setBusy(true);setError("");
    try{
      const result=await invoke<{id?:number;pending?:boolean}|null>("add_torrent_file");
      if(result)setDone(result.pending?"Torrent metadata lookup started.":"Torrent added successfully.");
    }catch(e){setError(String(e))}finally{setBusy(false)}
  };
  return <CrystalWindow target="details"><WindowTop noMax title={mode==="torrent"?"Add Torrent — Mister Hybrid Glass":"Add URL — Mister Hybrid Glass"}/>
    <div className="cg-window-add"><h2>{mode==="torrent"?"Add a BitTorrent download":"Add a new download"}</h2>
      <p>{mode==="torrent"?"Select a .torrent file or enter a magnet link. Both are handled by the original Rust MDM torrent engine.":"Enter a web download address. Browser links captured by the MDM extension also arrive automatically."}</p>
      {mode==="torrent"&&<button className="cg-btn" style={{alignSelf:"flex-start",marginBottom:20}}
        onClick={()=>void pickFile()} disabled={busy}><FileArchive size={18}/> Choose .torrent file…</button>}
      <label className="cg-field">{mode==="torrent"?"Magnet link":"Download address"}
        <input autoFocus placeholder={mode==="torrent"?"magnet:?xt=urn:btih:...":"https://example.com/file.zip"}
          value={url} onChange={e=>setUrl(e.target.value)} onKeyDown={e=>{if(e.key==="Enter")void save()}}/>
      </label>
      <label className="cg-toggle"><span><strong>Add to queue</strong><small>Don't begin downloading immediately</small></span>
        <input type="checkbox" checked={later} onChange={e=>setLater(e.target.checked)}/></label>
      {error&&<p className="cg-error">{error}</p>}
      {done&&<p className="cg-success">{done}</p>}
      <div className="cg-bottom-actions">
        <button className="cg-btn" onClick={()=>void getCurrentWindow().close()}><X size={16}/> Close</button>
        <button className="cg-btn cg-btn-primary" onClick={()=>void save()} disabled={busy||!url.trim()}>
          {mode==="torrent"?<Plus size={16}/>:<Download size={16}/>}
          {later?"Add to queue":"Start Download"}
        </button>
      </div>
      <div className="cg-muted" style={{fontSize:10,marginTop:15}}>
        <Link2 size={13}/> Download actions use the real MDM engine and existing saved settings.
      </div>
    </div>
  </CrystalWindow>;
}
