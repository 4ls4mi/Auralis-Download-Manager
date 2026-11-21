import test from 'node:test';
import assert from 'node:assert/strict';
import {receivingTubeSlots,lastReceivingRows} from '../src/tubeNetwork.ts';

test('tube flow represents only currently receiving engine connections',()=>{
 const connections=[{id:0,state:'Receiving',speed:20,downloaded:5},{id:9,state:'Receiving',speed:10,downloaded:5},{id:17,state:'Retrying',speed:0,downloaded:5},{id:31,state:'Receiving',speed:8,downloaded:9},{id:2,state:'Receiving',speed:0,downloaded:4,recent_disconnect:true},{id:33,state:'Receiving',speed:1,downloaded:1}];
 const slots=receivingTubeSlots(connections,true);assert.equal(slots.length,32);assert.deepEqual(slots.flatMap((active,i)=>active?[i]:[]),[0,9,31]);assert.deepEqual(lastReceivingRows(slots),[0,1,-1,-1,-1,-1,-1,3]);assert.ok(receivingTubeSlots(connections,false).every(active=>!active));assert.ok(receivingTubeSlots(undefined,true).every(active=>!active));
});
