import {useCallback,useEffect,useState} from 'react';
import {invoke} from '@tauri-apps/api/core';
import {getVersion} from '@tauri-apps/api/app';
import {useUpdateProgress, UpdateProgressView} from './useUpdateProgress';
type Status={state:string;version?:string;date?:string;message?:string;notes?:string};
export default function CrystalUpstream(){
 const [fork,setFork]=useState<Status>({state:'not-checked'}),[showNotes,setShowNotes]=useState(false),[busy,setBusy]=useState(false),[installing,setInstalling]=useState(false);
 const [progress,setProgress]=useUpdateProgress();
 const host=(globalThis as typeof globalThis & {__AURALIS_WINUI__?:{isolatedDownloads?:boolean;updateInstallSupported?:boolean}}).__AURALIS_WINUI__;
 const preview=host?.isolatedDownloads===true, installUnavailable=host?.updateInstallSupported===false;
 const [error,setError]=useState('');
 const [appVersion,setAppVersion]=useState('');
 useEffect(()=>{void getVersion().then(setAppVersion).catch(()=>setAppVersion('unavailable'))},[]);
 const check=useCallback(async()=>{setBusy(true);setError('');setInstalling(false);try{setFork(await invoke<Status>('glass_update_check'))}catch(e){setFork({state:'error',message:String(e)})}finally{setBusy(false)}},[]);
 useEffect(()=>{void check()},[check]);
 const forkLabel=fork.state==='available'?`Auralis ${fork.version} is available.`:fork.state==='latest'?'Auralis is up to date.':fork.state==='error'?`Update check failed: ${fork.message}`:'Check for a newer Auralis release.';
 const download=async()=>{setBusy(true);setError('');setProgress(null);setInstalling(false);try{await invoke('glass_update_download');setInstalling(true);await invoke('glass_update_install')}catch(e){setError(String(e));setInstalling(false);setBusy(false)}};
 return <><section className="cg-glass cg-progress-section"><h3>Auralis updates</h3><p>Current version: <strong>{appVersion||"Checking…"}</strong></p><p role="status">{busy?'Updating Auralis…':forkLabel}</p>{busy&&<UpdateProgressView progress={progress} installing={installing}/>}<div className="cg-bottom-actions"><button className="cg-btn cg-neon-violet" disabled={busy} onClick={()=>void check()}>Check for updates</button>{fork.state==='available'&&<><button className="cg-btn" onClick={()=>setShowNotes(!showNotes)}>{showNotes?'Close changelog':'Show changelog'}</button><button className="cg-btn cg-btn-primary" disabled={busy||installUnavailable} onClick={()=>void download()}>Download and install</button></>}</div>{showNotes&&<pre style={{whiteSpace:'pre-wrap',maxHeight:200,overflow:'auto'}}>{fork.notes||'No changelog provided.'}</pre>}{installUnavailable&&<p>{preview?"Update installation is unavailable in this development preview.":"Update installation is unavailable in this WinUI build."}</p>}{error&&<p className="cg-error" role="alert">{error}</p>}</section></>
}
