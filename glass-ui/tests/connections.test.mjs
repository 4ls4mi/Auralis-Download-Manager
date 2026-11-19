import {test} from 'node:test';
import assert from 'node:assert/strict';
import {connectionIndicators,connectionSlots,connectionLost} from '../src/connections.ts';
test('uses only engine-reported workers and their actual assigned ranges',()=>{
 const a=connectionIndicators([{id:5,downloaded:24,speed:2,state:'Receiving'},{id:3,downloaded:0,speed:0,state:'Retired'}],[{start:100,cursor:124,end:140,worker:5},{start:0,cursor:90,end:100,worker:null}]);
 assert.equal(a.length,1);assert.equal(a[0].id,5);assert.equal(a[0].percent,60);assert.equal(a[0].received,24);assert.equal(a[0].assigned,40);
});
test('does not invent assigned progress for missing or invalid range data',()=>{
 const a=connectionIndicators([{id:0,downloaded:20,speed:0,state:'Connecting'}],[{start:0,cursor:20,end:40},{start:0,cursor:99,end:40,worker:0}]);
 assert.equal(a.length,1);assert.equal(a[0].percent,null);assert.equal(a[0].assigned,null);
});
test('retains assigned progress for a worker after its ranges are released',()=>{
 const workers=[{id:1,downloaded:20,speed:0,state:'Finished'}];
 const a=connectionIndicators(workers,[{start:0,cursor:20,end:20,worker:null,last_worker:1},{start:20,cursor:25,end:40,worker:null,last_worker:1}]);
 assert.equal(a[0].assigned,40);assert.equal(a[0].percent,62.5);
});
test('shows one wide-capable indicator when a requested pool is reduced to one engine worker',()=>{
 const workers=[{id:0,downloaded:40,speed:2,state:'Receiving'},...Array.from({length:15},(_,i)=>({id:i+1,downloaded:0,speed:0,state:'Retired'}))];
 const a=connectionIndicators(workers,[{start:0,cursor:40,end:100,worker:0}]);
 assert.equal(a.length,1);assert.equal(a[0].percent,40);
});
test('does not impose a display limit on the number of reported connections',()=>{
 const workers=Array.from({length:160},(_,id)=>({id,downloaded:0,speed:0,state:'Connecting'}));
 assert.equal(connectionIndicators(workers,[]).length,160);
});

test('orders workers by their real identifiers, even when they report out of order',()=>{
 const workers=[{id:5,downloaded:0,speed:0,state:'Connecting'},{id:1,downloaded:0,speed:0,state:'Connecting'}];
 assert.deepEqual(connectionIndicators(workers,[]).map(c=>c.id),[1,5]);
});

test('detail slots stay fixed without inventing workers and cap the display at 32',()=>{
 const workers=Array.from({length:8},(_,id)=>({id}));
 const slots=connectionSlots(workers);assert.equal(slots.length,32);assert.equal(slots.filter(Boolean).length,8);assert(slots.slice(8).every(x=>x===null));
 const many=Array.from({length:40},(_,id)=>({id}));assert.equal(connectionSlots(many).length,32);assert.equal(connectionSlots(many)[31].id,31);assert.equal(connectionSlots(many,true).length,40);
});

test('connections keep their own block when another connection disappears and returns',()=>{
 const first=connectionSlots([{id:0},{id:1},{id:2}]);
 const disconnected=connectionSlots([{id:0},{id:2}]);
 const returned=connectionSlots([{id:0},{id:1},{id:2}]);
 assert.equal(first[2].id,2);assert.equal(disconnected[1],null);assert.equal(disconnected[2].id,2);assert.equal(returned[2].id,2);
});

test('a lost connection retains its measured fill and resumes from the same range',()=>{
 const range={start:100,cursor:140,end:200,worker:1,last_worker:1};
 const receiving=connectionIndicators([{id:1,downloaded:40,speed:10,state:'Receiving'}],[range])[0];
 const retrying=connectionIndicators([{id:1,downloaded:40,speed:0,state:'Retrying'}],[{...range,worker:null}])[0];
 const resumed=connectionIndicators([{id:1,downloaded:45,speed:10,state:'Receiving'}],[{...range,cursor:145}])[0];
 assert.equal(receiving.percent,40);assert.equal(retrying.percent,40);assert.equal(resumed.percent,45);
 assert.equal(connectionLost(retrying,true),true);
});

test('loss styling follows only reported retry, failure or recent disconnect',()=>{
 const base={id:0,downloaded:20,speed:0,state:'Receiving'};
 assert.equal(connectionLost(base,true),false);
 assert.equal(connectionLost({...base,state:'Retrying'},true),true);
 assert.equal(connectionLost({...base,state:'Failed'},true),true);
 assert.equal(connectionLost({...base,recent_disconnect:true},true),true);
 assert.equal(connectionLost({...base,state:'Connecting',reconnecting_after_loss:true},true),true);
 assert.equal(connectionLost({...base,state:'Connecting'},true),false);
 assert.equal(connectionLost({...base,state:'Retrying'},false),false);
 assert.equal(connectionLost({...base,state:'Finished',recent_disconnect:true},true),false);
 const [lost]=connectionIndicators([{...base,state:'Retrying'}],[{start:0,cursor:20,end:100,worker:null,last_worker:0}]);
 assert.equal(lost.percent,20);
 assert.equal(connectionIndicators([{...base,state:'Failed'}],[]).length,1);
 assert.equal(connectionIndicators([{...base,downloaded:0,state:'Failed',reconnecting_after_loss:true}],[]).length,1);
});
