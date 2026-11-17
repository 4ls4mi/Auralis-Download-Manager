import {test} from 'node:test';
import assert from 'node:assert/strict';
import {connectionIndicators} from '../src/connections.ts';
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
