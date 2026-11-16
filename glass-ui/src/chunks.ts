export type ByteRange = {start:number;cursor:number;end:number};
/** Stable, user-selected chunks. Their received bytes are intersections with
 * the original engine's live ranges, including adaptive splitting and resume.
 * This groups engine ranges without changing its downloader or inventing bytes. */
export function selectedChunks(count:number,size:number,ranges:ByteRange[]){
  const n=Math.max(1,Math.min(128,Math.trunc(count)||1));
  if(!Number.isFinite(size)||size<=0)return [];
  const ordered=ranges.filter(r=>Number.isFinite(r.start)&&Number.isFinite(r.cursor)&&r.cursor>r.start)
    .map(r=>({start:Math.max(0,r.start),end:Math.min(size,r.end,r.cursor)}))
    .filter(r=>r.end>r.start).sort((a,b)=>a.start-b.start);
  const received:{start:number;end:number}[]=[];
  for(const r of ordered){const last=received.at(-1);if(last&&r.start<=last.end)last.end=Math.max(last.end,r.end);else received.push({...r});}
  return Array.from({length:n},(_,i)=>{
    const start=Math.floor(size*i/n),end=Math.floor(size*(i+1)/n);
    const bytes=received.reduce((sum,r)=>sum+Math.max(0,Math.min(end,r.end)-Math.max(start,r.start)),0);
    return {start,end,received:bytes,percent:end>start?100*bytes/(end-start):0};
  });
}
