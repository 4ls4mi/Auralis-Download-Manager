import test from 'node:test';
import assert from 'node:assert/strict';
import {connectReleasePush} from '../src/releasePush.ts';

test('push client accepts release hints, checks after reconnect, and stops cleanly',()=>{
 const RealSocket=globalThis.WebSocket,realTimeout=globalThis.setTimeout,realClear=globalThis.clearTimeout,realNow=Date.now;
 const sockets=[],timers=[];let checks=0,reconnects=0,now=100000;
 class Socket{constructor(url){this.url=url;sockets.push(this)}close(){this.onclose?.()}}
 globalThis.WebSocket=Socket;globalThis.setTimeout=(fn,ms)=>{const t={fn,ms};timers.push(t);return t};globalThis.clearTimeout=()=>{};Date.now=()=>now;
 try{
  assert.throws(()=>connectReleasePush('http://example.com',()=>{},()=>{}));
  const stop=connectReleasePush('wss://example.com/events',()=>checks++,()=>reconnects++);
  sockets[0].onopen();assert.equal(reconnects,1);
  sockets[0].onmessage({data:'bad json'});sockets[0].onmessage({data:JSON.stringify({type:'release',version:'garbage'})});assert.equal(checks,0);
  sockets[0].onmessage({data:JSON.stringify({type:'release',version:'0.3.10'})});assert.equal(checks,1);
  sockets[0].onmessage({data:JSON.stringify({type:'release',version:'0.3.10'})});assert.equal(checks,1,'bursts must be throttled');
  now+=30001;sockets[0].onmessage({data:JSON.stringify({type:'release',version:'0.3.11'})});assert.equal(checks,2);
  sockets[0].onclose();assert.equal(timers[0].ms,2000);timers[0].fn();sockets[1].onopen();assert.equal(reconnects,2);
  stop();assert.equal(timers.length,1,'closing must not schedule another reconnect');
 }finally{globalThis.WebSocket=RealSocket;globalThis.setTimeout=realTimeout;globalThis.clearTimeout=realClear;Date.now=realNow}
});
