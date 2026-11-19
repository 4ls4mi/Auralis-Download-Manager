import test from 'node:test';
import assert from 'node:assert/strict';
import {frostedResizeDirection} from '../src/frostedResize.ts';
function mask(){const a=new Uint8ClampedArray(100*100*4);for(let y=20;y<80;y++)for(let x=20;x<80;x++)a[(y*100+x)*4+3]=255;return a}
test('visible glass edges map to their resize direction at different window scales',()=>{
 const a=mask(),check=(w,h,x,y)=>frostedResizeDirection(a,100,100,w,h,x,y);
 assert.equal(check(100,100,20,50),'West');assert.equal(check(100,100,79,50),'East');
 assert.equal(check(100,100,50,20),'North');assert.equal(check(100,100,50,79),'South');
 assert.equal(check(100,100,20,20),'NorthWest');assert.equal(check(100,100,79,79),'SouthEast');
 assert.equal(check(100,100,50,50),null);assert.equal(check(100,100,0,0),null);
 assert.equal(check(200,200,40,100),'West');assert.equal(check(200,200,100,40),'North');
});
