import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const root=process.cwd();
const out=path.join(root,"src-tauri","icons");
fs.mkdirSync(out,{recursive:true});
const size=256, rgba=Buffer.alloc(size*size*4);
const clamp=v=>Math.max(0,Math.min(255,Math.round(v)));
const mix=(a,b,t)=>a+(b-a)*t;
const stops=[[0,[65,245,255]],[.48,[57,139,255]],[1,[203,91,255]]];
function grad(t){for(let i=1;i<stops.length;i++)if(t<=stops[i][0]){const [p,a]=stops[i-1],[q,b]=stops[i];const u=(t-p)/(q-p);return a.map((v,k)=>mix(v,b[k],u));}return stops.at(-1)[1]}
function segDist(px,py,x1,y1,x2,y2){const dx=x2-x1,dy=y2-y1,t=Math.max(0,Math.min(1,((px-x1)*dx+(py-y1)*dy)/(dx*dx+dy*dy)));return Math.hypot(px-x1-t*dx,py-y1-t*dy)}
function rounded(px,py,x,y,w,h,r){const cx=Math.max(x+r,Math.min(px,x+w-r)),cy=Math.max(y+r,Math.min(py,y+h-r));return Math.hypot(px-cx,py-cy)-r}
function blend(dst,src,a){for(let k=0;k<3;k++)dst[k]=dst[k]*(1-a)+src[k]*a;dst[3]=255;}
for(let y=0;y<size;y++)for(let x=0;x<size;x++){
 const i=(y*size+x)*4, nx=(x-128)/128,ny=(y-128)/128;
 const edge=rounded(x+.5,y+.5,7,7,242,242,53);
 const inside=Math.max(0,Math.min(1,.5-edge));
 const glow=Math.max(0,1-Math.hypot(nx*.8,ny*.8))*0.18;
 let col=[mix(5,17,(y/size)),mix(14,24,(y/size)),mix(34,68,(y/size))].map(v=>v+glow*90);
 const halo=Math.max(0,1-Math.hypot(nx*1.05,ny*1.05))*0.12;
 col=[col[0]+halo*20,col[1]+halo*45,col[2]+halo*100,255];
 const border=Math.max(0,Math.min(1,2.2-Math.abs(edge)));
 const g=grad(x/(size-1));
 for(let k=0;k<3;k++)col[k]=mix(col[k],g[k],border*.92);
 const d1=segDist(x,y,49,204,128,39),d2=segDist(x,y,128,39,207,204);
 const bar=segDist(x,y,82,139,174,139);
 const shaft=segDist(x,y,128,92,128,177);
 const left=segDist(x,y,96,151,128,184),right=segDist(x,y,128,184,160,151);
 const d=Math.min(d1,d2,bar,shaft,left,right);
 const widths=[d1,d2].includes(d)?10:9;
 const core=Math.max(0,Math.min(1,(widths+1.4-d)*.9));
 const bloom=Math.max(0,Math.min(1,(widths+9-d)*.10))*.45;
 const ink=grad(x/(size-1));
 for(let k=0;k<3;k++)col[k]=mix(col[k],ink[k],Math.max(core,bloom));
 const shine=Math.max(0,1-Math.abs(y-42)/2)*Math.max(0,1-Math.abs(x-128)/90)*.65;
 col=col.map((v,k)=>k===3?255:mix(v,[190,255,255][k],shine));
 const alpha=inside;
 rgba[i]=clamp(col[0]);rgba[i+1]=clamp(col[1]);rgba[i+2]=clamp(col[2]);rgba[i+3]=clamp(alpha*255);
}
function crc32(buf){let c=0xffffffff;for(const b of buf){c^=b;for(let j=0;j<8;j++)c=(c>>>1)^((c&1)?0xedb88320:0)}return (c^0xffffffff)>>>0}
function chunk(type,data){const t=Buffer.from(type),len=Buffer.alloc(4),crc=Buffer.alloc(4);len.writeUInt32BE(data.length);crc.writeUInt32BE(crc32(Buffer.concat([t,data])));return Buffer.concat([len,t,data,crc])}
const rows=Buffer.alloc(size*(1+size*4));
for(let y=0;y<size;y++){const off=y*(1+size*4);rows[off]=0;for(let x=0;x<size;x++){const src=(y*size+x)*4,dst=off+1+x*4;rows[dst]=rgba[src];rows[dst+1]=rgba[src+1];rows[dst+2]=rgba[src+2];rows[dst+3]=rgba[src+3]}}
const ih=Buffer.alloc(13);ih.writeUInt32BE(size,0);ih.writeUInt32BE(size,4);ih[8]=8;ih[9]=6;
const png=Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk("IHDR",ih),chunk("IDAT",zlib.deflateSync(rows,{level:9})),chunk("IEND",Buffer.alloc(0))]);
fs.writeFileSync(path.join(out,"auralis.png"),png);
const header=Buffer.alloc(6);header.writeUInt16LE(0,0);header.writeUInt16LE(1,2);header.writeUInt16LE(1,4);
const entry=Buffer.alloc(16);entry[0]=0;entry[1]=0;entry[2]=0;entry[3]=0;entry.writeUInt16LE(1,4);entry.writeUInt16LE(32,6);entry.writeUInt32LE(png.length,8);entry.writeUInt32LE(22,12);
fs.writeFileSync(path.join(out,"auralis.ico"),Buffer.concat([header,entry,png]));
console.log("Generated Auralis 256px PNG and Windows ICO.");
