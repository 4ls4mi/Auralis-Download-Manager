/** A push message is only a hint. Callers always re-check GitHub for the
 * release and verify the installer; the server never provides a download URL. */
export function connectReleasePush(url:string,onSignal:()=>void,onReconnect:()=>void){
 const parsed=new URL(url);if(parsed.protocol!=='wss:'||parsed.username||parsed.password||parsed.search||parsed.hash)throw Error('Invalid release notification address');
 let closed=false,socket:WebSocket|undefined,timer:ReturnType<typeof setTimeout>|undefined,attempt=0,lastSignal=0,lastVersion="";
 const connect=()=>{
  if(closed)return;
  try{socket=new WebSocket(parsed.href)}catch{schedule();return}
  socket.onopen=()=>{if(closed)return;attempt=0;onReconnect()};
  socket.onmessage=event=>{if(typeof event.data!=='string'||event.data.length>256)return;try{const message=JSON.parse(event.data);if(message?.type!=='release'||typeof message.version!=='string'||!/^\d+\.\d+\.\d+$/.test(message.version))return;const now=Date.now();if(message.version===lastVersion&&now-lastSignal<30000)return;lastVersion=message.version;lastSignal=now;onSignal()}catch{/* Ignore malformed and untrusted signals. */}};
  socket.onerror=()=>socket?.close();
  socket.onclose=()=>{socket=undefined;schedule()};
 };
 const schedule=()=>{if(closed||timer)return;const delay=Math.min(60000,2000*2**Math.min(attempt++,5));timer=setTimeout(()=>{timer=undefined;connect()},delay)};
 connect();
 return()=>{closed=true;if(timer)clearTimeout(timer);socket?.close();socket=undefined};
}
