import {test} from 'node:test';
import assert from 'node:assert/strict';
import {connectionGrid,connectionIndicators} from '../src/connections.ts';
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

test('lays out at most eight connections per row within a bounded height',()=>{
 assert.deepEqual(connectionGrid(1,false),{columns:1,rows:1,height:24});
 assert.deepEqual(connectionGrid(8,false),{columns:8,rows:1,height:24});
 assert.deepEqual(connectionGrid(16,false),{columns:8,rows:2,height:48});
 assert.equal(connectionGrid(128,false).rows,16);assert.equal(connectionGrid(128,false).height,128);
 assert.equal(connectionGrid(160,true).columns,8);assert.equal(connectionGrid(160,true).height,26);
});
