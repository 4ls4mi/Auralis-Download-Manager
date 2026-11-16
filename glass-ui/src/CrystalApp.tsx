import { invoke } from "@tauri-apps/api/core";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import {
  Activity, Archive, CheckCircle2, Clock3, Download as DownloadIcon, File,
  FileArchive, Film, Folder, FolderOpen,
  Pause, Play, Plus, Search, Settings, Square, Trash2, ChevronDown,
  ListFilter
} from "lucide-react";
import {
  CrystalWindow, WindowTop, GradientBar, ChunkMap, SpeedGraph, pct, rate, units,
  timeLeft, openWindow
} from "./CrystalShared";
import type { Dashboard, Download as MdmFile, DownloadVisual, VisualDashboard } from "./CrystalShared";


import type { DeleteRequest } from "./CrystalDialog";

type Menu = "Tasks" | "File" | "Downloads" | "View" | "Help";
type MenuEntry = { label: string; action: string; disabled?: boolean; shortcut?: string; children?:MenuEntry[] };
const menus: Menu[]=["Tasks","File","Downloads","View","Help"];
const blank:Dashboard={downloads:[],speed:0,queues:[],categories:[]};
const pop = (id:number)=>openWindow("download-"+id,"/?detail="+id,880,680);
const settings = (tab="General")=>openWindow("settings","/?settings=1&tab="+encodeURIComponent(tab),880,695);
const add=(torrent=false)=>openWindow(torrent?"add-torrent":"add-url",`/?add=${torrent?"torrent":"url"}`,590,390);
const props=(id:number)=>openWindow("properties-"+id,"/?properties="+id,760,600);
const tool=(kind:string,id:number)=>openWindow(`tool-${kind}-${id}`,`/?tool=${kind}&id=${id}`,700,500);
function FileSymbol({name}:{name:string}){
  const ext=name.split(".").pop()?.toLowerCase();
  const Icon=["mp4","mkv","mov","avi","webm"].includes(ext??"")?Film:
    ["zip","rar","7z","iso","nsp","torrent"].includes(ext??"")?Archive:
      ["exe","msi"].includes(ext??"")?FileArchive:File;
  return <div className="cg-file-icon"><Icon size={21}/></div>;
}
function StatusBadge({item}:{item:MdmFile}){
  const label=item.status==="Complete"?"Completed":item.status==="Stopped"?"Paused":item.status;
  return <span className={"cg-status "+item.status.toLowerCase()}><span className="dot"/>{label}</span>;
}
export default function CrystalApp(){
  const [data,setData]=useState<Dashboard>(blank),[online,setOnline]=useState(false),[message,setMessage]=useState("Connecting to downloads…");
  const [chosen,setChosen]=useState<number|null>(null),[filter,setFilter]=useState("All Downloads"),[term,setTerm]=useState("");
  const [openMenu,setOpenMenu]=useState<Menu|null>(null),[context,setContext]=useState<{id:number;x:number;y:number}|null>(null);
  const [busy,setBusy]=useState(false),[error,setError]=useState(""),[history,setHistory]=useState<number[]>([]);
  const [visuals,setVisuals]=useState<Record<number,DownloadVisual>>({});
  const [fileRates,setFileRates]=useState<Record<number,number[]>>({});
  const [doubleClickOpen,setDoubleClickOpen]=useState(false);
  const [showCategories,setShowCategories]=useState(true);

  const [page,setPage]=useState(0),[capacity,setCapacity]=useState(8);
  const contextRef=useRef<HTMLDivElement>(null);
  const viewport=useRef<HTMLDivElement|null>(null);
  useEffect(()=>{const el=viewport.current;if(!el)return;const observer=new ResizeObserver(()=>setCapacity(Math.max(1,Math.floor((el.clientHeight-38)/82))));observer.observe(el);return()=>observer.disconnect()},[]);
  useLayoutEffect(()=>{
    const menu=contextRef.current;if(!menu)return;
    const fit=menu.closest<HTMLElement>('.cg-fit-content');if(!fit)return;
    const place=()=>{
      const host=fit.getBoundingClientRect(),scale=host.width/fit.offsetWidth;
      const maxHeight=(host.height-16)/scale;
      menu.style.zoom=String(Math.min(1,maxHeight/menu.scrollHeight));
      const resized=menu.getBoundingClientRect();
      menu.style.left=Math.max(8,Math.min(context?.x??8,(host.width-resized.width-8)/scale))+'px';
      menu.style.top=Math.max(8,Math.min(context?.y??8,(host.height-resized.height-8)/scale))+'px';
    };
    place();menu.addEventListener('toggle',place,true);return()=>menu.removeEventListener('toggle',place,true);
  },[context]);
  const pending=useRef(false),searchRef=useRef<HTMLInputElement|null>(null);
  const refresh=useCallback(async()=>{
    if(pending.current)return;
    pending.current=true;
    try{
      const next=await invoke<Dashboard>("dashboard_snapshot");
      setData(next);setOnline(true);setMessage("Ready");
      setHistory(h=>[...h.slice(-52),Math.max(0,next.speed)]);
      setFileRates(old=>{
        const updated={...old};
        for(const item of next.downloads)
          updated[item.id]=[...(old[item.id]??[]).slice(-45),Math.max(0,item.speed)];
        for(const key of Object.keys(updated))
          if(!next.downloads.some(item=>item.id===Number(key)))delete updated[Number(key)];
        return updated;
      });
      // The backend returns REAL byte-range segment cursors. The completion
      // percentage is independently calculated from downloaded/total bytes.
      const telemetry=await invoke<VisualDashboard>("dashboard_visuals").catch(()=>null);
      if(telemetry?.downloads)
        setVisuals(Object.fromEntries(telemetry.downloads.map(x=>[x.id,x])));
    }catch(e){setOnline(false);setMessage(String(e))}
    finally{pending.current=false}
  },[]);
  useEffect(()=>{
    let mounted=true;
    void invoke<string>("boot_engine").then(text=>{
      if(!mounted)return;
      setMessage(text);void refresh();
      void invoke<{double_click_open:boolean;confirm_delete:boolean;delete_files_too:boolean}>("glass_settings").then(s=>{
        if(mounted){setDoubleClickOpen(Boolean(s.double_click_open));}
      }).catch(()=>undefined);
    }).catch(e=>{if(mounted){setOnline(false);setMessage(String(e))}});
    const timer=window.setInterval(()=>{if(mounted)void refresh()},1200);
    return()=>{mounted=false;window.clearInterval(timer)}
  },[refresh]);
  useEffect(()=>{
    const changed=(event:StorageEvent)=>{if(event.key==="glass-downloads-changed")void refresh()};
    window.addEventListener("storage",changed);
    return()=>window.removeEventListener("storage",changed);
  },[refresh]);
  const counts=useMemo(()=>({
    all:data.downloads.length,downloading:data.downloads.filter(x=>x.status==="Downloading").length,
    stopped:data.downloads.filter(x=>x.status==="Stopped").length,
    unfinished:data.downloads.filter(x=>x.status!=="Complete").length,
    finished:data.downloads.filter(x=>x.status==="Complete").length
  }),[data.downloads]);
  const shown=useMemo(()=>data.downloads.filter(d=>{
    const match=filter==="All Downloads"||
      (filter==="Downloading"&&d.status==="Downloading")||
      (filter==="Stopped"&&d.status==="Stopped")||
      (filter==="Unfinished"&&d.status!=="Complete")||
      (filter==="Finished"&&d.status==="Complete")||
      (filter.startsWith("cat:")&&d.category===filter.slice(4))||
      (filter.startsWith("queue:")&&data.queues.find(q=>q.name===filter.slice(6))?.ids.includes(d.id));
    return match&&(d.file+" "+d.url+" "+d.path).toLowerCase().includes(term.toLowerCase())
  }),[data.downloads,data.queues,filter,term]);
  const picked=data.downloads.find(i=>i.id===chosen)??null;
  const anyRunning=counts.downloading>0,anyComplete=counts.finished>0;
  const mainQueue=data.queues[0];
  const remove=async(request:DeleteRequest)=>{
    setBusy(true);setError("");
    try{
      for(let start=0;start<request.ids.length;start+=100){
        const result=await invoke<{skipped:{why:string}[]}>("download_action",{action:request.disk?"delete":"remove",ids:request.ids.slice(start,start+100)});
        if(result.skipped.length)throw Error(result.skipped.map(x=>x.why).join("; "));
      }
      await invoke("glass_tool",{action:"original-setting",payload:{key:"delete_files_too",value:request.disk}});
      if(request.dontAsk){await invoke("update_glass_setting",{key:"confirm_delete",value:"false"});}
      await refresh();
    }catch(e){setError(String(e))}finally{setBusy(false)}
  };
  const execute=async(action:string,item:MdmFile|null=picked)=>{
    setOpenMenu(null);setContext(null);setError("");
    if(["remove","delete","delete-completed"].includes(action)){
      const items=action==="delete-completed"?data.downloads.filter(x=>x.status==="Complete"):item?[item]:[];
      if(!items.length)return;
      const request:DeleteRequest={ids:items.map(x=>x.id),name:items.length===1?items[0].file:`${items.length} completed downloads`,disk:action==="delete",dontAsk:false};
      const latest=await invoke<{confirm_delete:boolean;delete_files_too:boolean}>("glass_settings");
      request.disk=action==="delete"||latest.delete_files_too;
      if(latest.confirm_delete){localStorage.setItem("glass-delete-request",JSON.stringify(request));openWindow("tool-delete","/?tool=delete",620,410)}else await remove(request);
      return;
    }
    if(action==="open-with"&&item){try{await invoke("file_operation",{id:item.id,operation:"open-with",value:null})}catch(e){setError(String(e))}return}
    if(action==="move"&&item){try{await invoke("choose_move",{id:item.id});await refresh()}catch(e){setError(String(e))}return}
    if(["checksum","extract","refresh-address"].includes(action)&&item){tool(action,item.id);return}
    if(action.startsWith("queue-add:")&&item){try{await invoke("file_operation",{id:item.id,operation:"queue-add",value:action.slice(10)});await refresh()}catch(e){setError(String(e))}return}
    if(action==="queue-remove"&&item){try{await invoke("file_operation",{id:item.id,operation:"queue-remove",value:null});await refresh()}catch(e){setError(String(e))}return}
    if(action==="double-open"||action==="double-properties"){try{const on=action==="double-open";await invoke("update_glass_setting",{key:"double_click_open",value:String(on)});setDoubleClickOpen(on)}catch(e){setError(String(e))}return}
    if(action==="batch"||action==="grabber")return openWindow("tool-"+action,"/?tool="+action,action==="batch"?760:900,680);
    if(action==="add")return add();
    if(action==="torrent")return add(true);
    if(action==="settings")return settings();
    if(action==="scheduler")return openWindow("scheduler","/?schedule=1",860,660);
    if(action==="browser")return settings("Browser Integration");
    if(action==="appearance")return settings("Appearance");
    if(action==="limit")return settings("Connection");
    if(action==="about")return settings("Advanced");
    if(action==="refresh")return void refresh();
    if(action==="search"){searchRef.current?.focus();return}
    if(action==="toggle-categories"){setShowCategories(v=>!v);return}
    if(action==="details"){if(item)pop(item.id);return}
    if(action==="properties"){if(item)props(item.id);return}
    if(action==="hide"){void import("@tauri-apps/api/window").then(m=>m.getCurrentWindow().close());return}
    if(action==="exit"){
      localStorage.setItem("glass-confirm-request",JSON.stringify({action:"exit"}));
      openWindow("tool-confirm","/?tool=confirm",560,300);return;
    }
    if(!online){setError("The download service is unavailable.");return}
    setBusy(true);
    try{
      if(action==="stop-all"||action==="delete-completed"){

        const result=await invoke<{done:number[];skipped:{why:string}[]}>("bulk_action",{action});
        if(action==="stop-all")await invoke("close_progress_windows",{ids:result.done});
        if(result.skipped.length)setError(result.skipped.map(x=>x.why).join("; "));
      }else if(action==="queue-start"||action==="queue-stop"){
        if(!mainQueue)throw Error("No main queue exists");
        await invoke("queue_action",{name:mainQueue.name,action:action==="queue-start"?"start_queue":"stop_queue"});
      }else if(item&&(action==="start"||action==="stop"||action==="remove"||action==="delete")){
        const result=await invoke<{done:number[];skipped:{why:string}[]}>("download_action",{
          action:action==="stop"?"pause":action,ids:[item.id]
        });
        if(action==="stop")await invoke("close_progress_windows",{ids:result.done});
        if(result.skipped.length)setError(result.skipped.map(x=>x.why).join("; "));
      }else if(item&&(action==="open"||action==="folder"||action==="redownload")){
        if(action==="redownload"){localStorage.setItem("glass-confirm-request",JSON.stringify({action:"redownload",id:item.id,name:item.file}));openWindow("tool-confirm","/?tool=confirm",560,300);return;}
        await invoke("file_operation",{id:item.id,operation:action,value:null});
      }
      await refresh();
    }catch(e){setError(String(e))}
    finally{setBusy(false)}
  };
  function menuEntries(name:Menu):MenuEntry[]{
    switch(name){
      case "Tasks":return [
        {label:"Add new download…",action:"add",shortcut:"Ctrl+N"},
        {label:"Open torrent file / magnet…",action:"torrent",shortcut:"Ctrl+O"},
        {label:"Batch download…",action:"batch"},
        {label:"Link grabber…",action:"grabber"},
        {label:"Browser integration",action:"browser"},
        {label:"Hide in system tray",action:"hide"},
        {label:"Exit",action:"exit"}];
      case "File":return [
        {label:"Open",action:"open",disabled:!picked||picked.status!=="Complete"},
        {label:"Open folder",action:"folder",disabled:!picked},
        {label:"Move/Rename…",action:"move",disabled:!picked||picked.status==="Downloading"},
        {label:"Redownload",action:"redownload",disabled:!picked||picked.status==="Downloading"},
        {label:"Remove",action:"remove",disabled:!picked||picked.status==="Downloading",shortcut:"Delete"},
        {label:"Remove with files",action:"delete",shortcut:"Shift+Delete",disabled:!picked||picked.status==="Downloading"},
        {label:"Properties",action:"properties",disabled:!picked}];
      case "Downloads":return [
        {label:"Pause All / Stop All",action:"stop-all",disabled:!anyRunning},
        {label:"Delete All Completed",action:"delete-completed",disabled:!anyComplete},
        {label:"Scheduler…",action:"scheduler"},
        {label:"Start queue",action:"queue-start",disabled:!mainQueue||mainQueue.running},
        {label:"Stop queue",action:"queue-stop",disabled:!mainQueue||!mainQueue.running},
        {label:"Speed Limiter…",action:"limit"},
        {label:"Options",action:"settings"}];
      case "View":return [
        {label:showCategories?"Hide categories":"Show categories",action:"toggle-categories"},
        {label:"Refresh",action:"refresh",shortcut:"F5"},
        {label:"Search downloads…",action:"search",shortcut:"Ctrl+F"},
        {label:"Crystal Appearance…",action:"appearance"},
        {label:"Unified Settings…",action:"settings"}];
      case "Help":return [
        {label:"Browser integration and repair",action:"browser"},
        {label:"About Mister Hybrid Glass",action:"about"},
        {label:"Keyboard shortcuts",action:"about"}];
    }
  }
  useEffect(()=>{
    const keyboard=(e:KeyboardEvent)=>{
      if(e.key==="Escape"){setOpenMenu(null);setContext(null);return}
      if(e.ctrlKey&&e.key.toLowerCase()==="n"){e.preventDefault();void execute("add")}
      else if(e.ctrlKey&&e.key.toLowerCase()==="o"){e.preventDefault();void execute("torrent")}
      else if(e.ctrlKey&&e.key.toLowerCase()==="f"){e.preventDefault();searchRef.current?.focus()}
      else if(e.ctrlKey&&e.key===","){e.preventDefault();void execute("settings")}
      else if(e.key==="F5"){e.preventDefault();void refresh()}
      else if(e.ctrlKey&&e.key.toLowerCase()==="m"&&picked){e.preventDefault();void execute("move")}
      else if(e.key==="Delete"&&picked&&document.activeElement?.tagName!=="INPUT"){e.preventDefault();void execute(e.shiftKey?"delete":"remove")}
      else if(e.key==="Enter"&&picked&&document.activeElement?.tagName!=="INPUT"){e.preventDefault();pop(picked.id)}
    };
    const click=(e:MouseEvent)=>{
      if(!(e.target as HTMLElement).closest(".cg-menu-parent"))setOpenMenu(null);
      if(!(e.target as HTMLElement).closest(".cg-context"))setContext(null);
    };
    window.addEventListener("keydown",keyboard);document.addEventListener("mousedown",click);
    return()=>{window.removeEventListener("keydown",keyboard);document.removeEventListener("mousedown",click)}
  });
  const nav=[["All Downloads",DownloadIcon,counts.all],["Downloading",Activity,counts.downloading],
    ["Stopped",Pause,counts.stopped],["Unfinished",Clock3,counts.unfinished],["Finished",CheckCircle2,counts.finished]] as const;
  const toolbar=[
    {name:"Add URL",key:"add",icon:Plus,primary:true},
    {name:"Add Torrent",key:"torrent",icon:FileArchive},
    {name:"Resume",key:"start",icon:Play,disabled:!picked||picked.status==="Downloading"||picked.status==="Complete"},
    {name:"Stop",key:"stop",icon:Square,disabled:!picked||picked.status!=="Downloading",danger:true},
    {name:"Stop All",key:"stop-all",icon:Pause,disabled:!anyRunning,danger:true},
    {name:"Delete",key:"remove",icon:Trash2,disabled:!picked||picked.status==="Downloading",danger:true},
    {name:"Delete Completed",key:"delete-completed",icon:Trash2,disabled:!anyComplete,danger:true},
    {name:"Settings",key:"settings",icon:Settings},
    {name:"Scheduler",key:"scheduler",icon:Clock3},
    {name:"Start Queue",key:"queue-start",icon:Play,disabled:!mainQueue||mainQueue.running},
    {name:"Stop Queue",key:"queue-stop",icon:Pause,disabled:!mainQueue||!mainQueue.running,danger:true},
  ];
  const contextItems:MenuEntry[]=[
    {label:"Open",action:"open",disabled:!picked||picked.status!=="Complete"},
    {label:"Open with…",action:"open-with",disabled:!picked||picked.status!=="Complete"},
    {label:"Open folder",action:"folder",disabled:!picked},
    {label:"Move/Rename…",action:"move",disabled:!picked||picked.status==="Downloading",shortcut:"Ctrl+M"},
    {label:"Redownload",action:"redownload",disabled:!picked||picked.status==="Downloading"},
    {label:"Resume Download",action:"start",disabled:!picked||picked.status==="Downloading"||picked.status==="Complete"},
    {label:"Stop Download",action:"stop",disabled:!picked||picked.status!=="Downloading"},
    {label:"Refresh download address",action:"refresh-address",disabled:!picked||picked.status==="Downloading"||picked.status==="Complete"},
    {label:"Verify checksum…",action:"checksum",disabled:!picked},
    {label:"Extract",action:"extract",disabled:!picked||picked.status!=="Complete"||!(/\.(zip|7z|rar|tar|gz|xz)$/i.test(picked.file))},
    {label:"Remove",action:"remove",shortcut:"Delete",disabled:!picked||picked.status==="Downloading"},
    {label:"Remove with files",action:"delete",disabled:!picked||picked.status==="Downloading"},
    {label:"Add to queue",action:"move-queue",children:data.queues.map(q=>({label:q.name,action:"queue-add:"+q.name}))},
    {label:"Delete from queue",action:"queue-remove",disabled:!picked||!data.queues.some(q=>q.ids.includes(picked.id))},
    {label:"On Double-click",action:"double",children:[{label:"Open",action:"double-open"},{label:"Properties",action:"double-properties"}]},
    {label:"Properties",action:"properties",disabled:!picked}
  ];
  const rowDouble=(d:MdmFile)=>{
    if(d.status==="Complete"&&doubleClickOpen)void execute("open",d);
    else if(d.status==="Complete")openWindow(`complete-${d.id}`,`/?complete=${d.id}`,720,420);
    else pop(d.id);
  };
  const pageCount=Math.max(1,Math.ceil(shown.length/capacity)),safePage=Math.min(page,pageCount-1);
  return <CrystalWindow><WindowTop title="Mister Hybrid Glass — Download Manager">
    <span className="cg-muted" style={{fontSize:"var(--min-text-size)",whiteSpace:"nowrap",marginRight:9}}>{online?"● Connected":"○ Offline"}</span>
  </WindowTop>
  <div className="cg-main-body" onContextMenu={e=>e.preventDefault()}>
    <div className="cg-menubar">
      {menus.map(menu=><div className="cg-menu-parent" key={menu}>
        <button className={"cg-menu-trigger "+(openMenu===menu?"active":"")} onClick={()=>{setContext(null);setOpenMenu(openMenu===menu?null:menu)}}>{menu}</button>
        {openMenu===menu&&<div className="cg-dropdown">
          {menuEntries(menu).map(x=><button key={x.label} disabled={x.disabled} onClick={()=>void execute(x.action)}>
            <span>{x.label}</span>{x.shortcut&&<kbd>{x.shortcut}</kbd>}</button>)}
        </div>}
      </div>)}
    </div>
    <div className="cg-toolbar cg-glass">
      {toolbar.map((b,i)=><button key={i} data-action={b.key} className={`${b.primary?"primary":""} ${b.danger?"danger":""}`}
        disabled={busy||b.disabled} title={b.name} onClick={()=>void execute(b.key)}><b.icon size={19}/><span>{b.name}</span></button>)}
    </div>
    <div className="cg-workspace">
      {showCategories&&<aside className="cg-sidebar cg-glass">
        <div className="cg-side-heading">MISTER HYBRID • LIBRARY</div>
        {nav.map(([label,Icon,count])=><button key={label} className={filter===label?"selected":""} onClick={()=>setFilter(label)}>
          <Icon size={17}/><span>{label}</span><b>{count}</b></button>)}
        <div className="cg-side-separator">CATEGORIES</div>
        {data.categories.filter(c=>c.key!=="General").slice(0,10).map(c=><button className={filter==="cat:"+c.key?"selected":""}
          key={c.key} onClick={()=>setFilter("cat:"+c.key)}><Folder size={15}/><span>{c.name}</span></button>)}
        <div className="cg-side-separator">QUEUES</div>
        {data.queues.map(q=><button className={"cg-side-queue "+(filter==="queue:"+q.name?"selected":"")} key={q.name}
          onClick={()=>setFilter("queue:"+q.name)}><ListFilter size={15}/><span>{q.name}</span><b>{q.ids.length}</b></button>)}
      </aside>}
      <section className="cg-list-panel cg-glass">
        <header className="cg-list-title"><div><h2>{filter.startsWith("cat:")?filter.slice(4):filter.startsWith("queue:")?filter.slice(6):filter}</h2>
          <small>{shown.length} of {data.downloads.length} downloads • Double-click for the floating progress window</small></div>
          <label className="cg-search"><Search size={17}/><input ref={searchRef} placeholder="Search downloads..." value={term} onChange={e=>setTerm(e.target.value)}/></label>
        </header>
        <div className="cg-table-viewport" ref={viewport}><div className="cg-table">
          <header className="cg-cols"><span>FILE NAME</span><span>SIZE</span><span>STATUS</span><span>PROGRESS</span><span>SPEED</span><span>TIME LEFT</span></header>
          {shown.slice(safePage*capacity,(safePage+1)*capacity).map(d=><button className={"cg-row "+(chosen===d.id?"selected":"")} key={d.id}
            onClick={()=>{setChosen(d.id);setContext(null)}} onDoubleClick={()=>rowDouble(d)}
            onContextMenu={e=>{
              e.preventDefault();setChosen(d.id);setOpenMenu(null);
              const fit=e.currentTarget.closest<HTMLElement>(".cg-fit-content");if(fit){const box=fit.getBoundingClientRect(),scale=box.width/fit.offsetWidth;setContext({id:d.id,x:(e.clientX-box.left)/scale,y:(e.clientY-box.top)/scale});}
            }}>
            <span className="cg-file"><FileSymbol name={d.file}/><span className="cg-file-info">
              <strong title={d.file}>{d.file}</strong><small>{units(d.downloaded)} / {units(d.size)}</small></span></span>
            <span>{units(d.size)}</span><StatusBadge item={d}/>
            <span className="cg-row-progress">
              <GradientBar percent={pct(d)} showLabel/>
              <ChunkMap segments={visuals[d.id]?.segments} size={d.size} count={visuals[d.id]?.chunk_count} active={visuals[d.id]?.active_connections} compact/>
              <SpeedGraph values={fileRates[d.id]??[d.speed,d.speed]} small/>
            </span>
            <span>{d.status==="Downloading"?rate(d.speed):"—"}</span>
            <span>{timeLeft(d)}</span>
          </button>)}
          {!shown.length&&<div className="cg-empty"><FolderOpen size={35}/><strong>{online?"No downloads in this view":"Connecting to MDM"}</strong>
            <p>{online?"Add a URL or torrent to begin.":message}</p>
            {online&&<button className="cg-btn cg-btn-primary" onClick={()=>add()}><Plus size={15}/> Add URL</button>}
          </div>}
        </div></div>
        <div className="cg-pagination"><span>{shown.length} downloads</span><span className="cg-action-space"/><button disabled={!safePage} onClick={()=>setPage(p=>p-1)}>Previous</button><span>{safePage+1} / {pageCount}</span><button disabled={safePage>=pageCount-1} onClick={()=>setPage(p=>p+1)}>Next</button></div>
      </section>
    </div>
    <footer className="cg-footer cg-glass">
      <div className="cg-footer-stats"><span><small>TOTAL SPEED</small><strong>{rate(data.speed)}</strong></span>
        <span><small>ACTIVE</small><strong>{counts.downloading}</strong></span>
        <span><small>COMPLETED</small><strong>{counts.finished}</strong></span></div>
      <SpeedGraph values={history}/>
      <span className="cg-footer-message" title={error||message}>{error||message}</span>
    </footer>
    {context&&picked&&picked.id===context.id&&<div ref={contextRef} className="cg-context" style={{left:Math.max(10,context.x),top:Math.max(10,context.y)}}
      onContextMenu={e=>e.preventDefault()}>{contextItems.map(x=>x.children?<details key={x.label}><summary>{x.label}<ChevronDown size={13}/></summary><div className="cg-context-submenu">{x.children.map(c=><button key={c.label} onClick={()=>void execute(c.action,picked)}>{c.label}</button>)}</div></details>:<button key={x.label} disabled={x.disabled} onClick={()=>void execute(x.action,picked)}><span>{x.label}</span>{x.shortcut&&<kbd>{x.shortcut}</kbd>}</button>)}</div>}

  </div></CrystalWindow>;
}
