import test from 'node:test';
import assert from 'node:assert/strict';
import {frostedOutline} from '../src/frostedOutline.ts';
test('frosted outline follows the visible pixels instead of the rectangular window',()=>{
 const w=8,h=6,data=new Uint8ClampedArray(w*h*4);
 for(let y=1;y<5;y++)for(let x=y===1||y===4?2:1;x<(y===1||y===4?6:7);x++)data[(y*w+x)*4+3]=255;
 const points=frostedOutline(data,w,h);
 assert.equal(points.length,8);assert.deepEqual(points[0],[.25,1/6]);assert.deepEqual(points[1],[.125,2/6]);
 assert.ok(points.every(([x,y])=>x>=0&&x<=1&&y>=0&&y<=1));
 assert.deepEqual(frostedOutline(new Uint8ClampedArray(w*h*4),w,h),[]);
});
