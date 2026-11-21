import { invoke } from '@tauri-apps/api/core';
import { useEffect, useState } from 'react';
import { CalendarClock, Save } from 'lucide-react';
import { CrystalWindow, WindowTop } from './CrystalShared';
type Schedule={start_on_startup:boolean;start_at:[number,number,number]|null;days:boolean[];stop_at:[number,number,number]|null;retries:number|null;once:[number,number,number]|null;open_when_done:string|null;hang_up:boolean;exit_when_done:boolean;turn_off:string|null;force_close:boolean;wake:boolean};
type Queue={name:string;files_at_once:number;items:number[];sync:boolean;schedule:Schedule};
const time=(t:Schedule['start_at'])=>t?t.map(v=>String(v).padStart(2,'0')).join(':'):'';
const parseTime=(value:string):Schedule['start_at']=>value?value.split(':').map(Number).concat([0,0,0]).slice(0,3) as [number,number,number]:null;
export default function CrystalScheduler(){
 const [queues,setQueues]=useState<Queue[]>([]),[selected,setSelected]=useState(''),[draft,setDraft]=useState<Queue|null>(null),[panel,setPanel]=useState('Schedule'),[error,setError]=useState(''),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false);
 const choose=(q:Queue)=>{setDraft(structuredClone(q));setSelected(q.name);setNotice('')};
 useEffect(()=>{void invoke<{queues:Queue[]}>('glass_tool',{action:'queues',payload:null}).then(d=>{setQueues(d.queues);if(d.queues.length)choose(d.queues[0])}).catch(e=>setError(String(e)))},[]);
 const update=(key:keyof Schedule,value:Schedule[keyof Schedule])=>setDraft(old=>old?{...old,schedule:{...old.schedule,[key]:value}}:old);
 const checkbox=(key:keyof Schedule,label:string,detail:string)=><label className="cg-toggle"><span><strong>{label}</strong><small>{detail}</small></span><input type="checkbox" checked={Boolean(draft?.schedule[key])} onChange={e=>update(key,e.target.checked)}/></label>;
 const save=async()=>{if(!draft)return;setBusy(true);setError('');try{await invoke('glass_tool',{action:'schedule',payload:{name:draft.name,files_at_once:draft.files_at_once,schedule:draft.schedule}});setQueues(old=>old.map(q=>q.name===draft.name?draft:q));setNotice('Schedule saved.')}catch(e){setError(String(e))}finally{setBusy(false)}};
 const schedule=draft?.schedule;
 const host=(globalThis as typeof globalThis & {__AURALIS_WINUI__?:{isolatedDownloads?:boolean;supportsComputerActions?:boolean}}).__AURALIS_WINUI__;
 const preview=host?.supportsComputerActions===false;
 return <CrystalWindow target="details"><WindowTop title="Scheduler"/><main className="cg-page cg-scheduler-page"><header className="cg-property-heading"><CalendarClock size={23}/><h2>Scheduler</h2><label className="cg-inline-field" style={{marginLeft:'auto'}}>Queue<select value={selected} onChange={e=>{const q=queues.find(q=>q.name===e.target.value);if(q)choose(q)}}>{queues.map(q=><option key={q.name}>{q.name}</option>)}</select></label></header>
  <nav className="cg-appearance-tabs">{['Schedule','Completion'].map(name=><button key={name} className={panel===name?'selected':''} onClick={()=>setPanel(name)}>{name}</button>)}</nav>
  {draft&&schedule?panel==='Schedule'?<section className="cg-glass cg-progress-section">
   <label className="cg-toggle"><span><strong>Download files at the same time</strong><small>Maximum simultaneous downloads in this queue</small></span><input type="number" min="1" max="128" value={draft.files_at_once} onChange={e=>setDraft({...draft,files_at_once:Number(e.target.value)})}/></label>
   {checkbox('start_on_startup','Start queue on startup','Begin when the download manager starts')}
   <div className="cg-schedule-times"><label className="cg-field">Start at<input type="time" step="1" value={time(schedule.start_at)} onChange={e=>update('start_at',parseTime(e.target.value))}/></label><label className="cg-field">Stop at<input type="time" step="1" value={time(schedule.stop_at)} onChange={e=>update('stop_at',parseTime(e.target.value))}/></label></div>
   <div className="cg-weekdays">{['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].map((name,i)=><label key={name}><input type="checkbox" checked={schedule.days[i]} onChange={e=>{const days=[...schedule.days];days[i]=e.target.checked;update('days',days)}}/>{name}</label>)}</div>
   <div className="cg-schedule-times"><label className="cg-field">Once on date (optional)<input type="date" value={schedule.once?schedule.once.map((v,i)=>String(v).padStart(i?2:4,'0')).join('-'):''} onChange={e=>update('once',e.target.value?e.target.value.split('-').map(Number) as [number,number,number]:null)}/></label><label className="cg-field">Retries per failed file (blank = unlimited)<input type="number" min="0" value={schedule.retries??''} onChange={e=>update('retries',e.target.value===''?null:Number(e.target.value))}/></label></div>
   {preview?<p>Computer wake and completion actions are unavailable in this WinUI build.</p>:checkbox('wake','Wake the computer for this queue','Keep the computer awake while the queue runs')}
  </section>:preview?<section className="cg-glass cg-progress-section"><p>Computer and completion actions are unavailable in this WinUI build.</p></section>:<section className="cg-glass cg-progress-section"><label className="cg-field">Open this file when the queue finishes<input value={schedule.open_when_done??''} onChange={e=>update('open_when_done',e.target.value||null)}/></label>
   {checkbox('hang_up','Hang up when done','Disconnect an active Windows dial-up connection')}{checkbox('exit_when_done','Exit Auralis when done','Save the list and exit Auralis')}
   <label className="cg-toggle"><span><strong>Computer action</strong><small>A cancellable 30-second countdown appears first</small></span><select value={schedule.turn_off??''} onChange={e=>update('turn_off',e.target.value||null)}><option value="">No action</option><option value="ShutDown">Shut down</option><option value="Sleep">Sleep</option><option value="Hibernate">Hibernate</option></select></label>
   {checkbox('force_close','Force applications to close','Unsaved work may be lost')}
  </section>:<p className="cg-muted">No queues available.</p>}
  {error&&<p className="cg-error">{error}</p>}{notice&&<p className="cg-success">{notice}</p>}
  <div className="cg-bottom-actions" style={{marginTop:'auto'}}><button className="cg-btn" disabled={busy||!draft} onClick={async()=>{setError('');try{await invoke('queue_action',{name:selected,action:'start_queue'});setNotice('Queue started.')}catch(e){setError(String(e))}}} >Start queue</button><button className="cg-btn cg-neon-amber" disabled={busy||!draft} onClick={async()=>{try{await invoke('queue_action',{name:selected,action:'stop_queue'});setNotice('Queue stopped.')}catch(e){setError(String(e))}}} >Stop queue</button><span className="cg-action-space"/><button className="cg-btn cg-btn-primary" disabled={busy||!draft} onClick={()=>void save()}><Save size={15}/>Save schedule</button></div>
 </main></CrystalWindow>;
}
