import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DesktopCapture,mapCaptureRect} from '../src/rendering/desktopCapture.ts';
const makeGuard=()=>{const calls=[];return {calls,guard:{async arm(){calls.push('arm')},async disarm(){calls.push('disarm')}}}};
function makeStream(surface='monitor'){
 const track=new EventTarget();track.stopped=0;track.stop=()=>track.stopped++;track.getSettings=()=>({displaySurface:surface});
 return {track,stream:{getTracks:()=>[track],getVideoTracks:()=>[track]}};
}
test('capture only starts after protection and stops its stream before removing protection',async()=>{
 const {guard,calls}=makeGuard(),capture=new DesktopCapture(guard),{track,stream}=makeStream();
 await assert.rejects(capture.startFromClick(async()=>stream),/not armed/);await capture.arm();
 const received=await capture.startFromClick(async options=>{assert.equal(options.audio,false);return stream});assert.equal(received,stream);
 await capture.stop();assert.equal(track.stopped,1);assert.deepEqual(calls,['arm','disarm']);assert.equal(capture.status,'idle');
});
test('rejects window capture and releases protection if picker is cancelled',async()=>{
 const {guard,calls}=makeGuard(),capture=new DesktopCapture(guard),{track,stream}=makeStream('window');
 await capture.arm();await assert.rejects(capture.startFromClick(async()=>stream),/whole display/);assert.equal(track.stopped,1);assert.deepEqual(calls,['arm','disarm']);
 await capture.arm();await assert.rejects(capture.startFromClick(async()=>{throw Error('cancelled')}),/cancelled/);assert.deepEqual(calls,['arm','disarm','arm','disarm']);
});
test('maps negative-origin mixed-resolution displays and rejects spanning windows',()=>{
 assert.deepEqual(mapCaptureRect({x:-1920,y:0,width:1920,height:1080},{x:-1820,y:50,width:960,height:540},{width:3840,height:2160}),{x:200,y:100,width:1920,height:1080});
 assert.throws(()=>mapCaptureRect({x:0,y:0,width:100,height:100},{x:90,y:0,width:20,height:10},{width:100,height:100}),/outside/);
});
test('keeps protection until a pending picker closes',async()=>{
 const {guard,calls}=makeGuard(),capture=new DesktopCapture(guard),{track,stream}=makeStream();let resolve;
 await capture.arm();const start=capture.startFromClick(()=>new Promise(r=>{resolve=r}));const stopping=capture.stop();
 assert.deepEqual(calls,['arm']);resolve(stream);await assert.rejects(start,/cancelled/);await stopping;
 assert.ok(track.stopped>=1);assert.deepEqual(calls,['arm','disarm']);
});
