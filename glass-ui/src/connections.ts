export type ConnectionRange={start:number;cursor:number;end:number;worker?:number|null;last_worker?:number|null};
export type EngineConnection={id:number;downloaded:number;speed:number;state:string;recent_disconnect?:boolean;reconnecting_after_loss?:boolean};
/** Display only workers reported by the engine; never infer ownership from
 * equal divisions of the whole file. Assigned ranges may change dynamically. */
export function connectionIndicators(connections:EngineConnection[],ranges:ConnectionRange[]){
 return connections.filter(c=>c.state!=='Retired'&&!(c.state==='Failed'&&c.downloaded===0&&!c.recent_disconnect)&&!(c.state==='Finished'&&c.downloaded===0)).sort((a,b)=>a.id-b.id).map(c=>{
  const owned=ranges.filter(r=>(r.worker===c.id||(r.worker==null&&r.last_worker===c.id))&&Number.isFinite(r.start)&&Number.isFinite(r.cursor)&&Number.isFinite(r.end)&&r.end>r.start&&r.cursor>=r.start&&r.cursor<=r.end);
  const total=owned.reduce((s,r)=>s+r.end-r.start,0),received=owned.reduce((s,r)=>s+r.cursor-r.start,0);
  return {...c,assigned:total||null,received:total?received:null,percent:total?100*received/total:null};
 });
}

/** The detail window reserves exactly 32 places; empty places are not workers. */
export function connectionSlots<T>(workers:T[],compact=false):(T|null)[]{
 return compact?workers:Array.from({length:32},(_,index)=>workers[index]??null);
}

/** A connection loss is reported by the engine, never inferred from low speed. */
export function connectionLost(c:EngineConnection,downloading:boolean):boolean {
 return downloading && c.state!=='Finished' && (c.state==='Retrying'||c.state==='Failed'||c.reconnecting_after_loss===true||c.recent_disconnect===true);
}
