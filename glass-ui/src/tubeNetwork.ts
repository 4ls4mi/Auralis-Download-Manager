import {connectionLost} from './connections.ts';
import type {EngineConnection} from './connections.ts';
/** A lit inlet or branch always comes from an engine worker receiving now. */
export function receivingTubeSlots(connections:EngineConnection[]|undefined,downloading:boolean):boolean[]{
 const ids=new Set((connections??[]).filter(c=>downloading&&c.state==='Receiving'&&!connectionLost(c,true)&&Number.isInteger(c.id)&&c.id>=0&&c.id<32).map(c=>c.id));
 return Array.from({length:32},(_,id)=>ids.has(id));
}
export function lastReceivingRows(slots:boolean[]):number[]{
 return Array.from({length:8},(_,col)=>{for(let row=3;row>=0;row--)if(slots[row*8+col])return row;return -1});
}
