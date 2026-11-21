import test from 'node:test';
import assert from 'node:assert/strict';
import {updateToastPosition} from '../src/toastPosition.ts';
test('toast reserves space above Windows notifications and respects monitor scale',()=>{
 assert.deepEqual(updateToastPosition({position:{x:0,y:0},size:{width:1920,height:1040}},{width:400,height:150},1),{x:1504,y:614});
 assert.deepEqual(updateToastPosition({position:{x:-2560,y:-100},size:{width:2560,height:1400}},{width:600,height:225},1.5),{x:-624,y:661});
 assert.deepEqual(updateToastPosition({position:{x:0,y:0},size:{width:500,height:300}},{width:400,height:200},1),{x:84,y:0});
});
