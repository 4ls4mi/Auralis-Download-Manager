import {useEffect,useState} from 'react';
import {invoke} from '@tauri-apps/api/core';
import {availableMonitors,currentMonitor,getCurrentWindow} from '@tauri-apps/api/window';
import {PhysicalPosition} from '@tauri-apps/api/dpi';
import {openWindow} from './CrystalShared';
import {updateToastPosition} from './toastPosition';
export default function CrystalUpdateToast(){
 const [version]=useState(()=>{try{return JSON.parse(localStorage.getItem('auralis-update-notice')||'null')?.version||''}catch{return ''}});
 useEffect(()=>{let active=true;const w=getCurrentWindow();void (async()=>{try{const [current,size]=await Promise.all([currentMonitor(),w.outerSize()]);const monitor=current??(await availableMonitors())[0];if(monitor&&active){const {x,y}=updateToastPosition(monitor.workArea,size,monitor.scaleFactor);await w.setPosition(new PhysicalPosition(x,y))}}catch{/* Still show the notice if position information is unavailable. */}finally{if(active)void invoke('show_update_toast').catch(()=>undefined)}})();const timer=window.setTimeout(()=>void w.close(),120000);return()=>{active=false;window.clearTimeout(timer)}},[]);
 return <div className="cg-update-toast" role="status"><strong>Auralis update available</strong><span>Version {version} is ready to review.</span><div><button onClick={()=>{openWindow('tool-update-notice','/?tool=update-notice',680,520);void getCurrentWindow().close()}}>View update</button><button onClick={()=>void getCurrentWindow().close()}>Close</button></div></div>;
}
