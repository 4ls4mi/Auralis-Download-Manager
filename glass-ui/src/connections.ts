export type ConnectionRange={start:number;cursor:number;end:number;worker?:number|null;last_worker?:number|null};
export type EngineConnection={id:number;downloaded:number;speed:number;state:string};
/** Display only workers reported by the engine; never infer ownership from
 * equal divisions of the whole file. Assigned ranges may change dynamically. */
export function connectionIndicators(connections:EngineConnection[],ranges:ConnectionRange[]){
 return connections.filter(c=>c.state!=='Retired'&&c.state!=='Failed'&&!(c.state==='Finished'&&c.downloaded===0)).sort((a,b)=>a.id-b.id).map(c=>{
  const owned=ranges.filter(r=>(r.worker===c.id||(r.worker==null&&r.last_worker===c.id))&&Number.isFinite(r.start)&&Number.isFinite(r.cursor)&&Number.isFinite(r.end)&&r.end>r.start&&r.cursor>=r.start&&r.cursor<=r.end);
  const total=owned.reduce((s,r)=>s+r.end-r.start,0),received=owned.reduce((s,r)=>s+r.cursor-r.start,0);
  return {...c,assigned:total||null,received:total?received:null,percent:total?100*received/total:null};
 });
}

/** Fit engine workers in rows of at most eight, with a bounded height. */
export function connectionGrid(count:number,compact:boolean){
 const n=Number.isFinite(count)?Math.max(1,Math.floor(count)):1;
 const columns=Math.min(8,n),rows=Math.ceil(n/8);
 const height=compact?Math.min(26,Math.max(12,rows*10)):Math.min(128,Math.max(24,rows*24));
 return {columns,rows,height};
}
