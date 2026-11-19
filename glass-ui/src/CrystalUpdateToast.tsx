import {useEffect,useState} from 'react';
import {currentMonitor,getCurrentWindow} from '@tauri-apps/api/window';
import {PhysicalPosition} from '@tauri-apps/api/dpi';
import {openWindow} from './CrystalShared';
export default function CrystalUpdateToast(){
 const [version]=useState(()=>{try{return JSON.parse(localStorage.getItem('auralis-update-notice')||'null')?.version||''}catch{return ''}});
 useEffect(()=>{let active=true;const w=getCurrentWindow();void (async()=>{try{const [monitor,size]=await Promise.all([currentMonitor(),w.outerSize()]);if(!monitor||!active)return;const a=monitor.workArea;await w.setPosition(new PhysicalPosition(Math.max(a.position.x,a.position.x+a.size.width-size.width-16),Math.max(a.position.y,a.position.y+a.size.height-size.height-16)))}catch{/* The notice remains usable if monitor information is unavailable. */}})();const timer=window.setTimeout(()=>void w.close(),120000);return()=>{active=false;window.clearTimeout(timer)}},[]);
 return <div className="cg-update-toast"><strong>Auralis update available</strong><span>Version {version} is ready to review.</span><div><button onClick={()=>{openWindow('tool-update-notice','/?tool=update-notice',680,520);void getCurrentWindow().close()}}>View update</button><button onClick={()=>void getCurrentWindow().close()}>Close</button></div></div>;
}
