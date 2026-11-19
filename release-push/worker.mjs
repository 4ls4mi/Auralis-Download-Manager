// A public-release signal only. Clients must obtain release details and verify
// installers from GitHub; this service never sends an installer URL or code.
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

export default {
  async fetch(request,env){
    const url=new URL(request.url);
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
    for(let start=0;start<SHARDS;start+=4){
      const results=await Promise.all(Array.from({length:4},(_,i)=>{
        const hub=env.RELEASE_HUB.get(env.RELEASE_HUB.idFromName(`auralis-${start+i}`));
        return hub.fetch(new Request('https://hub.internal/publish',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({delivery,signal})}));
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
    if(url.pathname==='/events'&&request.headers.get('Upgrade')?.toLowerCase()==='websocket'){
      if(this.ctx.getWebSockets().length>=2048)return new Response('Connection limit reached',{status:503});
      const [client,server]=Object.values(new WebSocketPair());this.ctx.acceptWebSocket(server);
      return new Response(null,{status:101,webSocket:client});
    }
    if(url.pathname==='/publish'&&request.method==='POST'){
      const {delivery,signal}=await request.json();
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
