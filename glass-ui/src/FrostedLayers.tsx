import {useEffect,useRef,useState} from 'react';
import {frostFragment,frostVertex} from './frostedLayersShader';
import {frostedResizeDirection} from './frostedResize';
import {frostedOutline} from './frostedOutline';
import {getCurrentWindow} from '@tauri-apps/api/window';

/** Draw the supplied Water Bubble 3.5.1 pane stack behind Auralis controls. */
export default function FrostedLayers({maskBackdrop=false,tintHue=210,tintStrength=50,opacity=100}:{maskBackdrop?:boolean;tintHue?:number;tintStrength?:number;opacity?:number}){
 const canvas=useRef<HTMLCanvasElement>(null),[fallback,setFallback]=useState(false),[generation,setGeneration]=useState(0);
 useEffect(()=>{
  const el=canvas.current;if(!el)return;let disposed=false,frame=0,gl:WebGLRenderingContext|null=null;
  const failed=()=>{if(!disposed)setFallback(true)};
  const lost=(e:Event)=>{e.preventDefault();failed()};const restored=()=>setGeneration(n=>n+1);el.addEventListener('webglcontextlost',lost);el.addEventListener('webglcontextrestored',restored);
  try{
   gl=el.getContext('webgl',{alpha:true,premultipliedAlpha:false,depth:false,antialias:true});if(!gl)throw Error('WebGL unavailable');
   const ctx=gl;
   const compile=(type:number,source:string)=>{const shader=ctx.createShader(type);if(!shader)throw Error('Shader unavailable');ctx.shaderSource(shader,source);ctx.compileShader(shader);if(!ctx.getShaderParameter(shader,ctx.COMPILE_STATUS)){const message=ctx.getShaderInfoLog(shader);ctx.deleteShader(shader);throw Error(message||'Shader compile failed')}return shader};
   const vs=compile(ctx.VERTEX_SHADER,frostVertex),fs=compile(ctx.FRAGMENT_SHADER,frostFragment),program=ctx.createProgram();if(!program)throw Error('Program unavailable');
   ctx.attachShader(program,vs);ctx.attachShader(program,fs);ctx.linkProgram(program);if(!ctx.getProgramParameter(program,ctx.LINK_STATUS))throw Error(ctx.getProgramInfoLog(program)||'Shader link failed');
   ctx.useProgram(program);const buffer=ctx.createBuffer();if(!buffer)throw Error('Buffer unavailable');ctx.bindBuffer(ctx.ARRAY_BUFFER,buffer);ctx.bufferData(ctx.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),ctx.STATIC_DRAW);const position=ctx.getAttribLocation(program,'position');ctx.enableVertexAttribArray(position);ctx.vertexAttribPointer(position,2,ctx.FLOAT,false,0,0);
   const viewport=ctx.getUniformLocation(program,'viewport');
   const h=((tintHue%360)+360)%360/60,x=1-Math.abs(h%2-1);const rgb=h<1?[1,x,0]:h<2?[x,1,0]:h<3?[0,1,x]:h<4?[0,x,1]:h<5?[x,0,1]:[1,0,x];
   ctx.uniform3f(ctx.getUniformLocation(program,'themeTint'),rgb[0],rgb[1],rgb[2]);ctx.uniform1f(ctx.getUniformLocation(program,'themeStrength'),Math.max(0,Math.min(1,tintStrength/65)));
   ctx.uniform1f(ctx.getUniformLocation(program,'glassOpacity'),Math.max(.1,Math.min(1,opacity/100)));
   const host=el.closest<HTMLElement>('.cg-window');
   const maskCanvas=document.createElement('canvas');maskCanvas.width=1484;maskCanvas.height=1044;
   let alpha:Uint8ClampedArray|null=null;
   const applyMask=()=>{
    if(!host)return;
    const mask=maskCanvas.getContext('2d');if(!mask)return;
    mask.clearRect(0,0,maskCanvas.width,maskCanvas.height);
    mask.drawImage(el,0,0,maskCanvas.width,maskCanvas.height);
    alpha=mask.getImageData(0,0,maskCanvas.width,maskCanvas.height).data;
    host.classList.add('cg-frost-edge-ready');
    if(maskBackdrop){host.style.setProperty('--frost-shell-mask',`url("${maskCanvas.toDataURL('image/png')}")`);host.classList.add('cg-frost-mask-ready');}
    const outline=frostedOutline(alpha,maskCanvas.width,maskCanvas.height);
    if(outline.length)window.dispatchEvent(new CustomEvent('glass-frost-outline',{detail:outline}));
   };
   const edgeAt=(event:MouseEvent)=>{if(!alpha)return null;const target=event.target as Element|null;if(target?.closest('button,input,select,textarea,a,[role="button"],.cg-resize'))return null;const bounds=el.getBoundingClientRect();return frostedResizeDirection(alpha,maskCanvas.width,maskCanvas.height,bounds.width,bounds.height,event.clientX-bounds.left,event.clientY-bounds.top)};
   const mouseDown=(event:MouseEvent)=>{if(event.button!==0)return;const direction=edgeAt(event);if(!direction)return;event.preventDefault();event.stopPropagation();void getCurrentWindow().startResizeDragging(direction).catch(e=>window.dispatchEvent(new CustomEvent('glass-window-error',{detail:String(e)})))};
   const mouseMove=(event:MouseEvent)=>{if(!host)return;const direction=edgeAt(event);host.style.cursor=direction?({North:'n-resize',South:'s-resize',East:'e-resize',West:'w-resize',NorthEast:'ne-resize',NorthWest:'nw-resize',SouthEast:'se-resize',SouthWest:'sw-resize'} as const)[direction]:''};
   host?.addEventListener('mousedown',mouseDown,true);host?.addEventListener('mousemove',mouseMove);
   const draw=()=>{frame=0;if(disposed||document.hidden||ctx.isContextLost())return;const rect=el.getBoundingClientRect();if(!rect.width||!rect.height)return;const dpr=Math.min(window.devicePixelRatio||1,2),w=Math.max(1,Math.round(rect.width*dpr)),h=Math.max(1,Math.round(rect.height*dpr));if(el.width!==w||el.height!==h){el.width=w;el.height=h}ctx.viewport(0,0,w,h);ctx.useProgram(program);ctx.uniform2f(viewport,w,h);ctx.drawArrays(ctx.TRIANGLES,0,3);if(!alpha)applyMask();setFallback(false)};
   const request=()=>{if(!frame)frame=requestAnimationFrame(draw)};const observer=new ResizeObserver(request);observer.observe(el);document.addEventListener('visibilitychange',request);request();
   return()=>{disposed=true;cancelAnimationFrame(frame);observer.disconnect();host?.removeEventListener('mousedown',mouseDown,true);host?.removeEventListener('mousemove',mouseMove);host?.style.removeProperty('cursor');host?.classList.remove('cg-frost-edge-ready');host?.classList.remove('cg-frost-mask-ready');host?.style.removeProperty('--frost-shell-mask');document.removeEventListener('visibilitychange',request);el.removeEventListener('webglcontextlost',lost);el.removeEventListener('webglcontextrestored',restored);ctx.deleteBuffer(buffer);ctx.deleteProgram(program);ctx.deleteShader(vs);ctx.deleteShader(fs)};
  }catch{failed()}
  return()=>{disposed=true;cancelAnimationFrame(frame);el.removeEventListener('webglcontextlost',lost);el.removeEventListener('webglcontextrestored',restored)};
 },[generation,maskBackdrop,tintHue,tintStrength,opacity]);
 return <><div className="cg-frost-fallback" aria-hidden="true" hidden={!fallback}/><canvas ref={canvas} className="cg-frost-canvas" aria-hidden="true"/></>;
}
