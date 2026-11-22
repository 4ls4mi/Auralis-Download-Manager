import {useEffect,useRef,useState} from 'react';
import {frostFragment,frostVertex} from './frostedLayersShader';

/** Draw the supplied Water Bubble 3.5.1 pane stack behind Auralis controls. */
export default function FrostedLayers({tintHue=210,tintRgb,tintStrength=50,opacity=100}:{tintHue?:number;tintRgb?:[number,number,number];tintStrength?:number;opacity?:number}){
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
   const h=((tintHue%360)+360)%360/60,x=1-Math.abs(h%2-1);const rgb=tintRgb?tintRgb.map(v=>v/255):h<1?[1,x,0]:h<2?[x,1,0]:h<3?[0,1,x]:h<4?[0,x,1]:h<5?[x,0,1]:[1,0,x];
   ctx.uniform3f(ctx.getUniformLocation(program,'themeTint'),rgb[0],rgb[1],rgb[2]);ctx.uniform1f(ctx.getUniformLocation(program,'themeStrength'),Math.max(0,Math.min(1,tintStrength/65)));
   ctx.uniform1f(ctx.getUniformLocation(program,'neutralTint'),tintRgb?1:0);
   ctx.uniform1f(ctx.getUniformLocation(program,'glassOpacity'),Math.max(.1,Math.min(1,opacity/100)));
   const draw=()=>{frame=0;if(disposed||document.hidden||ctx.isContextLost())return;const rect=el.getBoundingClientRect();if(!rect.width||!rect.height)return;const dpr=Math.min(window.devicePixelRatio||1,2),w=Math.max(1,Math.round(rect.width*dpr)),h=Math.max(1,Math.round(rect.height*dpr));if(el.width!==w||el.height!==h){el.width=w;el.height=h}ctx.viewport(0,0,w,h);ctx.useProgram(program);ctx.uniform2f(viewport,w,h);ctx.drawArrays(ctx.TRIANGLES,0,3);setFallback(false)};
   const request=()=>{if(!frame)frame=requestAnimationFrame(draw)};const observer=new ResizeObserver(request);observer.observe(el);document.addEventListener('visibilitychange',request);request();
   return()=>{disposed=true;cancelAnimationFrame(frame);observer.disconnect();document.removeEventListener('visibilitychange',request);el.removeEventListener('webglcontextlost',lost);el.removeEventListener('webglcontextrestored',restored);ctx.deleteBuffer(buffer);ctx.deleteProgram(program);ctx.deleteShader(vs);ctx.deleteShader(fs)};
  }catch{failed()}
  return()=>{disposed=true;cancelAnimationFrame(frame);el.removeEventListener('webglcontextlost',lost);el.removeEventListener('webglcontextrestored',restored)};
 },[generation,tintHue,tintRgb,tintStrength,opacity]);
 return <><div className="cg-frost-fallback" aria-hidden="true" hidden={!fallback}/><canvas ref={canvas} className="cg-frost-canvas" aria-hidden="true"/></>;
}
