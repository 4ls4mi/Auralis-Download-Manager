import {renderLiquidGpu} from './liquidMaterialGpu';
import {useEffect,useId,useRef,useState} from 'react';

/** The three shared optical treatments. Geometry and the selected palette remain independent. */
export const liquidMaterials=[['liquid-glass','Sculpted Liquid Glass'],['liquid-crystal','Pressurized Crystal'],['liquid-aero','Soft Aero Water']] as const;
export const isLiquidMaterial=(s:string)=>liquidMaterials.some(([key])=>key===s);
const clamp=(n:number,a:number,b:number)=>Math.max(a,Math.min(b,n));
function tint(hex:string, white:number){const m=/^#([0-9a-f]{6})$/i.exec(hex);if(!m)return hex;let n=parseInt(m[1],16);return '#'+[16,8,0].map(shift=>Math.round((n>>shift&255)*(1-white)+255*white).toString(16).padStart(2,'0')).join('')}
/** Smaller files animate faster, within restrained limits; absent sizes use a middle speed. */
export function liquidDuration(size?:number|null){return size&&size>0?clamp(1.3+Math.log10(Math.max(1,size/1024))*0.55,1.3,5.2):2.8}

// One animation clock per WebView rather than one RAF loop per download row.
const visible=new Set<(time:number)=>void>();let raf=0,last=0;
function frame(time:number){raf=0;if(document.hidden)return;if(time-last>1000/30){last=time;for(const fn of visible)fn(time)}if(visible.size)raf=requestAnimationFrame(frame)}
function add(fn:(time:number)=>void){visible.add(fn);if(!raf&&!document.hidden)raf=requestAnimationFrame(frame)}
function remove(fn:(time:number)=>void){visible.delete(fn);if(!visible.size&&raf){cancelAnimationFrame(raf);raf=0}}
if(typeof document!=='undefined')document.addEventListener('visibilitychange',()=>{if(!document.hidden&&visible.size&&!raf)raf=requestAnimationFrame(frame)});

export function LiquidProgress({percent,colors,material,size,active=true}:{percent:number;colors:string[];material:string;size?:number|null;active?:boolean}){
 const canvas=useRef<HTMLCanvasElement>(null);const colorKey=colors.join(',');
 useEffect(()=>{const node=canvas.current;if(!node)return;let inView=false,stopped=false;const reduce=matchMedia('(prefers-reduced-motion: reduce)');let width=0,height=0;
 const draw=(now:number)=>{if(stopped||!width||!height)return;const ctx=node.getContext('2d');if(!ctx)return;const dpr=Math.min(devicePixelRatio||1,2),w=width,h=height,W=Math.max(1,Math.round(w*dpr)),H=Math.max(1,Math.round(h*dpr));if(node.width!==W||node.height!==H){node.width=W;node.height=H}ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,w,h);const f=clamp(percent/100,0,1),end=w*f;if(end<=0)return;
  const t=active&&!reduce.matches?now/1000:0,speed=2*Math.PI/liquidDuration(size),phase=t*speed,reach=Math.min(h*.34,end*.5),mix=(1+Math.sin(phase*.62))*.5,shift=Math.min(mix,1-mix),top=end-reach*(1-mix-shift),bottom=end-reach*(mix-shift);
  const edge=(q:number)=>{const q1=q*q*(3-2*q),wiggle=.25*Math.sin(q*Math.PI*2-phase*2)*Math.sin(Math.PI*q);return clamp(top+(bottom-top)*clamp(q1+wiggle,0,1),0,end)};
  ctx.save();ctx.beginPath();ctx.moveTo(0,0);ctx.lineTo(edge(0),0);for(let j=0;j<=24;j++){const q=j/24;ctx.lineTo(edge(q),q*h)}ctx.lineTo(0,h);ctx.closePath();ctx.clip();
  const gpu=renderLiquidGpu(W,H,t,material,colors);if(gpu){ctx.drawImage(gpu,0,0,w,h)}else{
  const g=ctx.createLinearGradient(0,0,w,0);g.addColorStop(0,colors[0]||'#18cfff');g.addColorStop(.5,colors[1]||'#306cff');g.addColorStop(1,colors[2]||'#a344ff');ctx.fillStyle=g;ctx.fillRect(0,0,end,h);
  const shade=ctx.createLinearGradient(0,0,0,h);if(material==='liquid-crystal'){shade.addColorStop(0,'rgba(255,255,255,.9)');shade.addColorStop(.10,'rgba(255,255,255,.30)');shade.addColorStop(.35,'rgba(0,18,85,.16)');shade.addColorStop(.75,'rgba(0,8,46,.48)');shade.addColorStop(.94,'rgba(255,255,255,.18)');shade.addColorStop(1,'rgba(255,255,255,.75)')}else if(material==='liquid-aero'){shade.addColorStop(0,'rgba(255,255,255,.78)');shade.addColorStop(.16,'rgba(255,255,255,.25)');shade.addColorStop(.52,'rgba(0,12,65,.32)');shade.addColorStop(.88,'rgba(0,10,50,.16)');shade.addColorStop(1,'rgba(233,255,255,.55)')}else{shade.addColorStop(0,'rgba(255,255,255,.85)');shade.addColorStop(.13,'rgba(255,255,255,.22)');shade.addColorStop(.40,'rgba(0,15,65,.18)');shade.addColorStop(.79,'rgba(0,5,52,.46)');shade.addColorStop(1,'rgba(220,255,255,.52)')}ctx.fillStyle=shade;ctx.fillRect(0,0,end,h);
  // A curved reflection gives each material its own optical profile, without
  // tinting the selected palette or putting an opaque layer over the fill.
  ctx.beginPath();ctx.moveTo(0,h*.10);ctx.bezierCurveTo(end*.25,-h*.07,end*.45,h*.42,end*.67,h*.13);ctx.bezierCurveTo(end*.83,-h*.03,end*.94,h*.08,end,h*.05);ctx.lineTo(end,0);ctx.lineTo(0,0);ctx.closePath();
  const glint=ctx.createLinearGradient(0,0,0,h*.45);glint.addColorStop(0,material==='liquid-crystal'?'rgba(255,255,255,.86)':material==='liquid-aero'?'rgba(255,255,255,.66)':'rgba(255,255,255,.72)');glint.addColorStop(1,'rgba(255,255,255,0)');ctx.fillStyle=glint;ctx.fill();
  if(material==='liquid-crystal'){ctx.strokeStyle='rgba(235,255,255,.65)';ctx.lineWidth=Math.max(.6,h*.035);ctx.beginPath();ctx.moveTo(0,h*.09);ctx.lineTo(end,h*.09);ctx.moveTo(0,h*.90);ctx.lineTo(end,h*.90);ctx.stroke()}
  // Broad refracted highlights move inside the actual fill, never outside the track.
  for(let j=0;j<3;j++){const xx=((t*(20+j*8)+j*w*.37)%(w+80))-40,yy=h*(.30+j*.18),r=Math.max(h,20)*1.8;const light=ctx.createRadialGradient(xx,yy,0,xx,yy,r);light.addColorStop(0,tint(colors[j%3]||'#80dfff',.75)+'55');light.addColorStop(1,'#ffffff00');ctx.fillStyle=light;ctx.fillRect(xx-r,yy-r,2*r,2*r)}
  }
  if(material==='liquid-glass'&&h>=12){for(let j=0;j<5;j++){const xx=((j*67+t*(11+j*3))%(Math.max(1,end+12)))-6,yy=h*(.25+.13*(j%4));ctx.beginPath();ctx.arc(xx,yy,Math.max(.7,h*.04),0,Math.PI*2);ctx.strokeStyle='rgba(220,255,255,.55)';ctx.lineWidth=.7;ctx.stroke()}}
  ctx.restore();ctx.beginPath();for(let j=0;j<=24;j++){const q=j/24;j?ctx.lineTo(edge(q),h*q):ctx.moveTo(edge(q),0)}ctx.strokeStyle='rgba(230,255,255,.75)';ctx.lineWidth=material==='liquid-crystal'?1.4:.9;ctx.stroke();
  // A maximum of two small droplets: emerge at the front, then fall near its base.
  if(active&&!reduce.matches&&f<.98&&end>h){const cycle=Math.floor(t*speed/5),age=(t*speed/5)%1,random=(n:number)=>{const value=Math.sin((cycle+1)*127.1+n*311.7)*43758.5453;return value-Math.floor(value)},count=random(1)<.5?1:2;for(let j=0;j<count;j++){const a=age-j*.05;if(a<0||a>.64)continue;const q=.18+.64*random(2+j),start=edge(q),yy=h*q,launch=clamp(a/.11,0,1),travel=clamp((a-.11)/.41,0,1),range=Math.min(w-end,h*(2.2+.6*random(5+j))),px=start+launch*h*.12+travel*range,py=yy+travel*travel*(h-yy-1)-Math.sin(Math.PI*travel)*h*.10,r=clamp(h*.055,.75,2.4)*launch;if(a>.52){const impact=(a-.52)/.12;ctx.save();ctx.globalAlpha=1-impact;ctx.strokeStyle=tint(colors[0]||'#40bfff',.6);ctx.lineWidth=.7;ctx.beginPath();ctx.ellipse(px,h-1,Math.max(.5,impact*h*.18),Math.max(.25,impact*h*.035),0,Math.PI,2*Math.PI);ctx.stroke();ctx.restore();continue}if(!travel){ctx.beginPath();ctx.moveTo(start-1,yy);ctx.lineTo(px,py);ctx.strokeStyle=tint(colors[1]||'#40bfff',.55);ctx.lineWidth=Math.max(1,r);ctx.stroke()}if(r>0){const d=ctx.createRadialGradient(px-r*.3,py-r*.4,0,px,py,r);d.addColorStop(0,'#ffffff');d.addColorStop(.45,tint(colors[0]||'#40bfff',.45));d.addColorStop(1,colors[1]||'#168be2');ctx.fillStyle=d;ctx.beginPath();ctx.arc(px,py,r,0,Math.PI*2);ctx.fill()}}}
 };
 const resize=()=>{const r=node.getBoundingClientRect();width=r.width;height=r.height;draw(performance.now())};const ro=new ResizeObserver(resize);ro.observe(node);
 const update=()=>{remove(draw);if(inView&&active&&!reduce.matches)add(draw);draw(performance.now())};const io=new IntersectionObserver(entries=>{inView=entries.some(e=>e.isIntersecting);update()});io.observe(node);reduce.addEventListener('change',update);resize();return()=>{stopped=true;remove(draw);ro.disconnect();io.disconnect();reduce.removeEventListener('change',update)};
 },[percent,colorKey,material,size,active]);return <canvas ref={canvas} className={'cg-liquid-progress '+material} aria-hidden="true"/>;
}

export function LiquidChunk({percent,colors,material,animate,index=0}:{percent:number;colors:string[];material:string;animate:boolean;index?:number}){
 const id=useId().replace(/:/g,'');const p=clamp(percent,0,100),top=100-p;
 const [reduced,setReduced]=useState(()=>typeof matchMedia==='function'&&matchMedia('(prefers-reduced-motion: reduce)').matches);
 useEffect(()=>{const media=matchMedia('(prefers-reduced-motion: reduce)'),onChange=()=>setReduced(media.matches);media.addEventListener('change',onChange);return()=>media.removeEventListener('change',onChange)},[]);
 const light=material==='liquid-crystal'?.95:material==='liquid-aero'?.48:.72,shadow=material==='liquid-crystal'?.7:material==='liquid-aero'?.35:.5;
 const surface=(left:number,right:number)=>`M0 ${top+left} Q25 ${top-left} 50 ${top+1} Q75 ${top-right} 100 ${top+right}`;
 const closed=(left:number,right:number)=>`${surface(left,right)} L100 100 L0 100 Z`;
 const surfaceFrames=[surface(1,5),surface(4,1),surface(1,5)],waterFrames=[closed(1,5),closed(4,1),closed(1,5)];if(index%2){surfaceFrames.splice(0,3,surface(4,1),surface(1,5),surface(4,1));waterFrames.splice(0,3,closed(4,1),closed(1,5),closed(4,1))}
 const motion=animate&&!reduced&&p<99,duration=`${1.55+(index%4)*.13}s`;
 const moving=(frames:string[])=>motion?<animate attributeName="d" values={frames.join(';')} dur={duration} repeatCount="indefinite"/>:null;
 return <svg className={'cg-liquid-chunk '+material+(motion?' moving':'')} viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id={id} x1="0" x2="0" y1="0" y2="1"><stop stopColor={tint(colors[0]||'#18cfff',.65)}/><stop offset=".24" stopColor={colors[0]}/><stop offset=".62" stopColor={colors[1]}/><stop offset="1" stopColor={colors[2]}/></linearGradient><linearGradient id={id+'shine'} x1="0" x2="0" y1="0" y2="1"><stop stopColor="#fff" stopOpacity={light}/><stop offset=".25" stopColor="#fff" stopOpacity=".08"/><stop offset="1" stopColor="#00112e" stopOpacity={shadow}/></linearGradient></defs>{motion&&p<94&&<g className="cg-inlet-droplet"><ellipse cx="50" cy="4" rx="3.4" ry="5.2" fill={colors[0]} stroke="rgba(235,255,255,.9)" strokeWidth=".8"><animate attributeName="cy" values={`4;${Math.max(5,top-3)}`} dur={`${.8+(index%4)*.13}s`} begin={`${(index%5)*-.17}s`} repeatCount="indefinite"/><animate attributeName="opacity" values="0;.95;.95;0" keyTimes="0;.12;.8;1" dur={`${.8+(index%4)*.13}s`} begin={`${(index%5)*-.17}s`} repeatCount="indefinite"/></ellipse></g>}<path d={waterFrames[0]} fill={`url(#${id})`}>{moving(waterFrames)}</path><path d={waterFrames[0]} fill={`url(#${id}shine)`}>{moving(waterFrames)}</path><path className="cg-liquid-surface" d={surfaceFrames[0]} fill="none" stroke="rgba(230,255,255,.8)" strokeWidth="1.2" vectorEffect="non-scaling-stroke">{moving(surfaceFrames)}</path>{material==='liquid-glass'&&p>25&&<circle cx="32" cy={top+p*.52} r="3" fill="none" stroke="rgba(235,255,255,.5)" strokeWidth="1"/>}{motion&&p<90&&<circle className="cg-liquid-splash" style={{animationDuration:duration}} cx={index%2?'16':'84'} cy={Math.max(3,top-5)} r="3.5" fill={tint(colors[0]||'#18cfff',.7)}/>}</svg>;
}
