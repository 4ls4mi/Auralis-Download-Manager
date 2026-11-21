import { invoke } from '@tauri-apps/api/core';
import { useEffect, useState } from 'react';
type Plan={hang_up:boolean;exit:boolean;turn_off:'ShutDown'|'Sleep'|'Hibernate'|null;force:boolean};
const empty:Plan={hang_up:false,exit:false,turn_off:null,force:false};
export default function CrystalCompletionOptions({id}:{id:number}){
 const [plan,setPlan]=useState<Plan>(empty),[show,setShow]=useState(true),[loaded,setLoaded]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const load=async()=>{const [settings,details]=await Promise.all([invoke<{show_complete:boolean}>('glass_settings'),invoke<{completion:Plan}>('file_operation',{id,operation:'details',value:null})]);setShow(settings.show_complete);setPlan(details.completion??empty);setLoaded(true)};
 useEffect(()=>{void load().catch(e=>setError(String(e)))},[id]);
 const update=async(next:Plan)=>{setBusy(true);setError('');try{await invoke('file_operation',{id,operation:'completion-options',value:JSON.stringify(next)});setPlan(next)}catch(e){setError(String(e))}finally{setBusy(false)}};
 const disabled=busy||!loaded||show;
 return <section className="cg-glass cg-progress-section"><h3>Options on completion</h3><label className="cg-toggle"><span><strong>Show download complete dialog</strong><small>Applies to all downloads</small></span><input type="checkbox" disabled={busy||!loaded} checked={show} onChange={async e=>{const checked=e.target.checked,previous=show;setShow(checked);setBusy(true);setError('');try{await invoke('update_glass_setting',{key:'show_complete',value:String(checked)});await load()}catch(e){setShow(previous);setError(String(e))}finally{setBusy(false)}}}/></label>
  <p className="cg-muted cg-completion-help">Automatic completion actions are available when the completion dialog is off.</p>
  <label className="cg-toggle"><span><strong>Hang up when complete</strong><small>Disconnect an active Windows dial-up connection</small></span><input type="checkbox" disabled={disabled} checked={plan.hang_up} onChange={e=>void update({...plan,hang_up:e.target.checked})}/></label>
  <label className="cg-toggle"><span><strong>Exit Auralis when complete</strong><small>Save the download list and close Auralis</small></span><input type="checkbox" disabled={disabled} checked={plan.exit} onChange={e=>void update({...plan,exit:e.target.checked})}/></label>
  <label className="cg-toggle"><span><strong>Turn off computer when complete</strong><small>A cancellable 30-second confirmation appears first</small></span><select aria-label="Computer action on completion" disabled={disabled} value={plan.turn_off??''} onChange={e=>void update({...plan,turn_off:(e.target.value||null) as Plan['turn_off']})}><option value="">No action</option><option value="ShutDown">Shut down</option><option value="Sleep">Sleep</option><option value="Hibernate">Hibernate</option></select></label>
  <label className="cg-toggle"><span><strong>Force applications to close</strong><small>Use only after saving your work</small></span><input type="checkbox" disabled={disabled||!plan.turn_off} checked={plan.force} onChange={e=>void update({...plan,force:e.target.checked})}/></label>
  {error&&<p className="cg-error" role="alert">{error}</p>}
 </section>;
}
