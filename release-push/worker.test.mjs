import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import worker,{releaseSignal,releaseMetadata,validSignature,ReleaseHub} from './worker.mjs';
const secret='test-secret';
const payload={action:'published',repository:{full_name:'4ls4mi/Auralis-Download-Manager'},release:{tag_name:'v0.3.10',draft:false,prerelease:false,assets:[{name:'Auralis.Download.Manager_0.3.10_x64-setup.exe'}]}};
const body=JSON.stringify(payload),signed='sha256='+createHmac('sha256',secret).update(body).digest('hex');
test('accepts only correctly signed messages',async()=>{assert.equal(await validSignature(secret,new TextEncoder().encode(body),signed),true);assert.equal(await validSignature('wrong',new TextEncoder().encode(body),signed),false)});
test('signals only public stable releases with an Auralis installer',()=>{
 assert.deepEqual(releaseSignal('release',payload),{type:'release',version:'0.3.10'});
 for(const edit of [{action:'edited'},{release:{...payload.release,draft:true}},{release:{...payload.release,prerelease:true}},{release:{...payload.release,assets:[]}},{repository:{full_name:'other/repo'}}])assert.equal(releaseSignal('release',{...payload,...edit}),null);
 assert.equal(releaseSignal('push',payload),null);
});
test('forwards authenticated public releases and rejects forged requests',async()=>{
 const sent=[];const env={GITHUB_WEBHOOK_SECRET:secret,RELEASE_HUB:{idFromName:()=>1,get:()=>({fetch:async r=>{sent.push(await r.json());return new Response(null,{status:204})}})}};
 const req=signature=>new Request('https://example.test/github/webhook',{method:'POST',headers:{'x-hub-signature-256':signature,'x-github-event':'release','x-github-delivery':'01234567-89ab-cdef-0123-456789abcdef'},body});
 assert.equal((await worker.fetch(req('sha256='+'0'.repeat(64)),env)).status,401);
 assert.equal((await worker.fetch(req(signed),env)).status,204);assert.equal(sent.length,16);assert.equal(sent[0].signal.version,'0.3.10');
});
test('broadcast deduplicates repeated GitHub delivery IDs',async()=>{
 const store=new Map(),messages=[];const ctx={storage:{get:async k=>store.get(k),put:async(k,v)=>store.set(k,v)},getWebSockets:()=>[{send:m=>messages.push(JSON.parse(m))}]};
 const hub=new ReleaseHub(ctx),publish=()=>hub.fetch(new Request('https://hub.internal/publish',{method:'POST',body:JSON.stringify({delivery:'same',signal:{type:'release',version:'0.3.10'}})}));
 await publish();await publish();assert.equal(messages.length,1);
});
test('only valid public release metadata can populate the fallback feed',()=>{
 const enriched=structuredClone(payload);Object.assign(enriched.release.assets[0],{browser_download_url:'https://github.com/4ls4mi/Auralis-Download-Manager/releases/download/v0.3.10/Auralis.Download.Manager_0.3.10_x64-setup.exe',digest:'sha256:'+'a'.repeat(64),size:123});enriched.release.body='Changes';
 const signal=releaseSignal('release',enriched),metadata=releaseMetadata(enriched,signal);
 assert.equal(metadata.assets[0].size,123);assert.equal(metadata.body,'Changes');
 for(const changed of [{digest:'sha256:bad'},{browser_download_url:'https://evil.example/a.exe'},{size:0},{size:300*1024*1024}]){const copy=structuredClone(enriched);Object.assign(copy.release.assets[0],changed);assert.equal(releaseMetadata(copy,signal),null)}
 assert.equal(releaseMetadata(enriched,null),null);
});
test('fallback stores the newest release and ignores an older redelivery',async()=>{
 const store=new Map(),ctx={storage:{get:async k=>store.get(k),put:async(k,v)=>store.set(k,v)},getWebSockets:()=>[]};const hub=new ReleaseHub(ctx);
 const publish=(tag,delivery)=>hub.fetch(new Request('https://hub.internal/publish',{method:'POST',body:JSON.stringify({delivery,signal:{type:'release',version:tag.slice(1)},metadata:{tag_name:tag}})}));
 assert.equal((await hub.fetch(new Request('https://hub.internal/latest'))).status,503);
 await publish('v0.3.30','new');await publish('v0.3.29','old');
 const response=await hub.fetch(new Request('https://hub.internal/latest'));assert.equal((await response.json())[0].tag_name,'v0.3.30');assert.equal(response.headers.get('Cache-Control'),'no-store');
});
