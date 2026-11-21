import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../../auralis-extension/background.js',import.meta.url),'utf8');
test('browser sign-in checks session cookies without leaking them to status',{timeout:5000},async()=>{
 const queries=[],opened=[];let signedIn=true;const ext={cookies:{getAll:async query=>{queries.push(query);if(query.url.includes('youtube.com'))return signedIn?[{name:'SID',value:'private-session',domain:'.youtube.com',path:'/',secure:true}]:[];if(query.url.includes('google.com'))return [{name:'G',value:'private-google-session',domain:'.google.com',path:'/',secure:true}];return []}},tabs:{create:async tab=>opened.push(tab.url)}};
 const context=vm.createContext({ext,URL});const functions=source.slice(source.indexOf('async function cookiesFor('),source.indexOf('// The cookies of a tab\'s stream'));vm.runInContext(functions+'\nthis.testVideoCookies=videoCookies;',context);const login=source.slice(source.indexOf('async function youtubeSignIn('),source.indexOf('async function pageMessage('));vm.runInContext(login+'\nthis.testSignIn=youtubeSignIn;',context);
 const result=await context.testVideoCookies('https://www.youtube.com/watch?v=test',{storeId:'container-1'});assert.equal(result.cookieJar.length,1);assert.ok(queries.every(q=>q.storeId==='container-1'));assert.equal(result.cookies,'SID=private-session');const status=await context.testSignIn({tab:{cookieStoreId:'container-1'}});assert.equal(status.signedIn,true);assert.equal(JSON.stringify(status).includes('private-session'),false);assert.equal(opened.length,0);
 signedIn=false;const missing=await context.testSignIn({tab:{cookieStoreId:'container-1'}});assert.equal(missing.signedIn,false);assert.match(opened[0],/^https:\/\/accounts\.google\.com\/ServiceLogin/);
});

test('explicit browser-session video lookup passes scoped Google and YouTube cookies',async()=>{
 const sent=[];const tab={id:1,cookieStoreId:'container-1'};const context=vm.createContext({remoteTarget:async()=>false,readStatus:async()=>({videoLookup:true}),videoTarget:async()=>({own:'https://www.youtube.com/watch?v=x',cookieJar:[],cookies:''}),isYouTube:url=>url.includes('youtube.com'),videoCookies:async(url,ctx)=>({cookieJar:[{domain:new URL(url).hostname,path:'/',name:'SID',value:'secret'}]}),native:async message=>{sent.push(message);return {lookup:{state:'pending'}}},URL});const code=source.slice(source.indexOf('async function videoLookup('),source.indexOf('async function videoPoll('));vm.runInContext(code+'\nthis.testLookup=videoLookup;',context);await context.testLookup({cookieMode:'browser',includeGoogleCookies:true},'https://www.youtube.com/watch?v=x',{tab});assert.equal(sent[0].explicitVideoCookies,true);assert.ok(sent[0].cookieJar.some(c=>c.domain==='www.youtube.com'));assert.ok(sent[0].cookieJar.some(c=>c.domain==='accounts.google.com'));
});

test('a video lookup refreshes a stale unsupported status before giving up',async()=>{
 let supported=false, refreshed=0, sent=0;
 const context=vm.createContext({remoteTarget:async()=>false,readStatus:async()=>({videoLookup:supported}),refreshRules:async()=>{refreshed++;supported=true},videoTarget:async()=>({own:'https://example.com/watch',cookieJar:[],cookies:''}),isYouTube:()=>false,native:async()=>{sent++;return {lookup:{state:'pending'}}},URL});
 const code=source.slice(source.indexOf('async function videoLookup('),source.indexOf('async function videoPoll('));vm.runInContext(code+'\nthis.lookup=videoLookup;',context);
 const result=await context.lookup({cookieMode:'browser'},'https://example.com/watch',{tab:{id:1}});assert.equal(refreshed,1);assert.equal(sent,1);assert.equal(result.lookup.state,'pending');
});

test('temporary native-host errors do not disable video capability',async()=>{
 let disabled=false;
 const context=vm.createContext({remoteTarget:async()=>false,readStatus:async()=>({videoLookup:true}),videoTarget:async()=>({own:'https://example.com/watch',cookieJar:[],cookies:''}),isYouTube:()=>false,native:async()=>({ok:false,why:'not-running'}),noteLookup:async()=>{disabled=true},URL});
 const code=source.slice(source.indexOf('async function videoLookup('),source.indexOf('async function videoPoll('));vm.runInContext(code+'\nthis.lookup=videoLookup;',context);
 const result=await context.lookup({cookieMode:'browser'},'https://example.com/watch',{tab:{id:1}});assert.equal(result.lookup.reason,'connection');assert.match(result.lookup.message,/not-running/);assert.equal(disabled,false);
});
