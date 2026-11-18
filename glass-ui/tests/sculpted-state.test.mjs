import test from 'node:test';
import assert from 'node:assert/strict';
import {sculptedPercent, sculptedPartPercent, sculptedConnectionState} from '../src/sculptedState.ts';

test('shaped tracks clamp missing and invalid progress without inventing data',()=>{
 assert.equal(sculptedPercent(null),0);assert.equal(sculptedPercent(NaN),0);
 assert.equal(sculptedPercent(-8),0);assert.equal(sculptedPercent(170),100);
});
test('separate links fill in order; parallel paths retain matching progress',()=>{
 assert.deepEqual(Array.from({length:5},(_,i)=>sculptedPartPercent(45,5,i,true)),[100,100,25,0,0]);
 assert.deepEqual(Array.from({length:2},(_,i)=>sculptedPartPercent(45,2,i,false)),[45,45]);
});
test('a lost connection preserves progress over red; pause makes the whole track red',()=>{
 assert.deepEqual(sculptedConnectionState(43,false,true),{percent:43,red:true});
 assert.deepEqual(sculptedConnectionState(43,true,false),{percent:0,red:true});
 assert.deepEqual(sculptedConnectionState(43,false,false),{percent:43,red:false});
 assert.deepEqual(sculptedConnectionState(null,false,true),{percent:0,red:true});
});
