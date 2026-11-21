// Signed GitHub release events provide notifications and cached release metadata.
// Installers still come only from GitHub and are verified by size and SHA-256.
const REPOSITORY = '4ls4mi/Auralis-Download-Manager';
const MAX_WEBHOOK_BYTES = 512 * 1024;
const SHARDS = 16;
const TAG = /^v?(\d+\.\d+\.\d+)$/i;
const encoder = new TextEncoder();

export async function validSignature(secret, body, header) {
  if (!secret || !/^sha256=[0-9a-f]{64}$/i.test(header || '')) return false;
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), {name:'HMAC',hash:'SHA-256'}, false, ['sign']);
  const expected = new Uint8Array(await crypto.subtle.sign('HMAC', key, body));
  const supplied = header.slice(7).match(/../g).map(x=>parseInt(x,16));
  let difference = 0;
  for (let i=0;i<expected.length;i++) difference |= expected[i] ^ supplied[i];
  return difference === 0;
}

export function releaseSignal(event, payload) {
  if(event!=='release'||payload?.action!=='published'||payload?.repository?.full_name?.toLowerCase()!==REPOSITORY.toLowerCase())return null;
  const r=payload.release, match=typeof r?.tag_name==='string'?TAG.exec(r.tag_name):null;
  if(!match||r.draft!==false||r.prerelease!==false||!Array.isArray(r.assets))return null;
  const version=match[1];
  const names=[`Auralis.Download.Manager_${version}_x64-setup.exe`,`Auralis Download Manager_${version}_x64-setup.exe`];
  if(r.assets.filter(a=>names.includes(a?.name)).length!==1)return null;
  return {type:'release',version};
}

export function releaseMetadata(payload,signal){
  const r=payload?.release;if(!signal||!r)return null;
  const version=signal.version, name=`Auralis.Download.Manager_${version}_x64-setup.exe`, legacy=`Auralis Download Manager_${version}_x64-setup.exe`;
  const asset=r.assets.find(a=>a?.name===name||a?.name===legacy);
  const prefix=`https://github.com/${REPOSITORY}/releases/download/${r.tag_name}/`;
  if(!asset||typeof asset.browser_download_url!=='string'||!asset.browser_download_url.startsWith(prefix)||/[?#]/.test(asset.browser_download_url)||!/^sha256:[0-9a-f]{64}$/i.test(asset.digest||'')||!Number.isSafeInteger(asset.size)||asset.size<1||asset.size>256*1024*1024)return null;
  return {tag_name:r.tag_name,draft:false,prerelease:false,body:typeof r.body==='string'?r.body.slice(0,50000):'',assets:[{name:asset.name,browser_download_url:asset.browser_download_url,digest:asset.digest,size:asset.size}]};
}
function newerOrEqual(a,b){const x=a.replace(/^v/i,'').split('.').map(Number),y=b.replace(/^v/i,'').split('.').map(Number);for(let i=0;i<3;i++){if(x[i]!==y[i])return x[i]>y[i]}return true}

export default {
  async fetch(request,env){
    const url=new URL(request.url);
    if(url.pathname==='/latest'&&request.method==='GET')return env.RELEASE_HUB.get(env.RELEASE_HUB.idFromName('auralis-0')).fetch(new Request('https://hub.internal/latest'));
    if(url.pathname==='/events' && request.method==='GET'){
      if(request.headers.get('Upgrade')?.toLowerCase()!=='websocket')return new Response('WebSocket required',{status:426});
      const shard=crypto.getRandomValues(new Uint32Array(1))[0]%SHARDS;
      return env.RELEASE_HUB.get(env.RELEASE_HUB.idFromName(`auralis-${shard}`)).fetch(request);
    }
    if(url.pathname!=='/github/webhook'||request.method!=='POST')return new Response('Not found',{status:404});
    if(!env.GITHUB_WEBHOOK_SECRET)return new Response('Service not configured',{status:503});
    const length=Number(request.headers.get('content-length')||0);
    if(length>MAX_WEBHOOK_BYTES)return new Response('Payload too large',{status:413});
    const bytes=await request.arrayBuffer();if(bytes.byteLength>MAX_WEBHOOK_BYTES)return new Response('Payload too large',{status:413});
    if(!await validSignature(env.GITHUB_WEBHOOK_SECRET,bytes,request.headers.get('x-hub-signature-256')))return new Response('Invalid signature',{status:401});
    let payload;try{payload=JSON.parse(new TextDecoder().decode(bytes))}catch{return new Response('Invalid JSON',{status:400})}
    const signal=releaseSignal(request.headers.get('x-github-event'),payload);
    if(!signal)return new Response(null,{status:204});
    const delivery=request.headers.get('x-github-delivery')||'';
    if(!/^[0-9a-f-]{36}$/i.test(delivery))return new Response('Invalid delivery id',{status:400});
    // Bound concurrent subrequests; if any shard fails GitHub may redeliver.
    const metadata=releaseMetadata(payload,signal);
    for(let start=0;start<SHARDS;start+=4){
      const results=await Promise.all(Array.from({length:4},(_,i)=>{
        const hub=env.RELEASE_HUB.get(env.RELEASE_HUB.idFromName(`auralis-${start+i}`));
        return hub.fetch(new Request('https://hub.internal/publish',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({delivery,signal,metadata:start+i===0?metadata:null})}));
      }));
      if(results.some(result=>!result.ok))return new Response('Notification delivery failed',{status:503});
    }
    return new Response(null,{status:204});
  }
};

// Cloudflare Durable Object: hibernating sockets remain connected while idle.
export class ReleaseHub {
  constructor(ctx){this.ctx=ctx}
  async fetch(request){
    const url=new URL(request.url);
    if(url.pathname==='/latest'&&request.method==='GET'){
      const latest=await this.ctx.storage.get('latest-release');
      return latest?Response.json([latest],{headers:{'Cache-Control':'no-store'}}):new Response('No release metadata available',{status:503});
    }
    if(url.pathname==='/events'&&request.headers.get('Upgrade')?.toLowerCase()==='websocket'){
      if(this.ctx.getWebSockets().length>=2048)return new Response('Connection limit reached',{status:503});
      const [client,server]=Object.values(new WebSocketPair());this.ctx.acceptWebSocket(server);
      return new Response(null,{status:101,webSocket:client});
    }
    if(url.pathname==='/publish'&&request.method==='POST'){
      const {delivery,signal,metadata}=await request.json();
      if(metadata){const previous=await this.ctx.storage.get('latest-release');if(!previous||newerOrEqual(metadata.tag_name,previous.tag_name))await this.ctx.storage.put('latest-release',metadata)}
      const previous=await this.ctx.storage.get('recent-deliveries')||[];
      if(previous.includes(delivery))return new Response(null,{status:204});
      for(const socket of this.ctx.getWebSockets()){try{socket.send(JSON.stringify(signal))}catch{try{socket.close()}catch{}}}
      await this.ctx.storage.put('recent-deliveries',[...previous.slice(-63),delivery]);
      return new Response(null,{status:204});
    }
    return new Response('Not found',{status:404});
  }
  webSocketMessage(socket){socket.close(1008,'Messages are not accepted')}
  webSocketError(socket){try{socket.close()}catch{}}
}
