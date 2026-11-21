import test from 'node:test';
import assert from 'node:assert/strict';
import { selectedChunks } from '../src/chunks.ts';
test('the selected 8 or 32 chunks are stable and independently reflect engine ranges',()=>{
 const ranges=[{start:0,cursor:50,end:100},{start:400,cursor:500,end:600}];
 const eight=selectedChunks(8,800,ranges);
 assert.equal(eight.length,8);assert.equal(eight[0].percent,50);assert.equal(eight[1].percent,0);assert.equal(eight[4].percent,100);
 assert.equal(selectedChunks(32,800,ranges).length,32);
 assert.equal(eight.reduce((s,c)=>s+c.received,0),150);
});
test('adaptive splits, overlapping snapshots and resume never duplicate bytes',()=>{
 const chunks=selectedChunks(8,800,[{start:0,cursor:200,end:300},{start:50,cursor:160,end:200},{start:200,cursor:450,end:500}]);
 assert.equal(chunks.reduce((s,c)=>s+c.received,0),450);
 assert.equal(chunks[4].percent,50);assert(chunks.every(c=>c.percent>=0&&c.percent<=100));
});
test('missing segment telemetry never invents downloaded bytes',()=>{
 assert(selectedChunks(32,800,[]).every(c=>c.received===0));assert.deepEqual(selectedChunks(8,0,[]),[]);
});
