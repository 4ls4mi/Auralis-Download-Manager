import {useEffect, useRef, useState} from "react";
import {frostVertex} from "./frostedLayersShader";
import {ribbonFragment} from "./frostedRibbonShader";

// All bars share one context: hundreds of downloads must not exhaust the GPU
// context limit. Each bar copies its current rendering into a 2D canvas.
let renderer: {canvas: HTMLCanvasElement; gl: WebGLRenderingContext; program: WebGLProgram} | null | undefined;
function getRenderer() {
  if (renderer !== undefined && !renderer?.gl.isContextLost()) return renderer;
  try {
    const canvas=document.createElement("canvas");
    const gl=canvas.getContext("webgl",{alpha:true,premultipliedAlpha:false,preserveDrawingBuffer:true,depth:false});
    if (!gl) throw Error("WebGL unavailable");
    const compile=(type:number,source:string)=>{const shader=gl.createShader(type);if(!shader)throw Error("Shader unavailable");gl.shaderSource(shader,source);gl.compileShader(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(shader)||"Shader compile failed");return shader};
    const vs=compile(gl.VERTEX_SHADER,frostVertex),fs=compile(gl.FRAGMENT_SHADER,ribbonFragment),program=gl.createProgram();
    if(!program)throw Error("Program unavailable");gl.attachShader(program,vs);gl.attachShader(program,fs);gl.linkProgram(program);
    if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(program)||"Shader link failed");
    gl.deleteShader(vs);gl.deleteShader(fs);gl.useProgram(program);
    const buffer=gl.createBuffer();if(!buffer)throw Error("Buffer unavailable");gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);
    const position=gl.getAttribLocation(program,"position");gl.enableVertexAttribArray(position);gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);
    renderer={canvas,gl,program};
  } catch { renderer=null }
  return renderer;
}
export default function FrostedRibbon({percent, colors, fallback, finish, tint, tintColors}:{percent:number;colors:string[];fallback:string;finish:string;tint:string;tintColors?:string[]}) {
  const ref=useRef<HTMLCanvasElement>(null),[failed,setFailed]=useState(false);
  useEffect(()=>{
    const target=ref.current;if(!target)return;
    const draw=()=>{
      const r=getRenderer(),ctx=target.getContext("2d"),rect=target.getBoundingClientRect();
      if(!r||!ctx){setFailed(true);return} if(!rect.width||!rect.height)return;
      const scale=Math.min(devicePixelRatio||1,2),w=Math.max(1,Math.round(rect.width*scale)),h=Math.max(1,Math.round(rect.height*scale));
      if(target.width!==w||target.height!==h){target.width=w;target.height=h}
      if(r.canvas.width!==w||r.canvas.height!==h){r.canvas.width=w;r.canvas.height=h}
      r.gl.viewport(0,0,w,h);r.gl.useProgram(r.program);
      r.gl.uniform2f(r.gl.getUniformLocation(r.program,"viewport"),w,h);
      r.gl.uniform1f(r.gl.getUniformLocation(r.program,"progress"),Math.max(0,Math.min(1,percent/100)));
      r.gl.uniform1f(r.gl.getUniformLocation(r.program,"trackFinish"),({default:0,clear:0,frosted:1,recessed:2} as Record<string,number>)[finish]??0);
      const tc=({ice:[.46,.75,.9],violet:[.63,.45,.82],teal:[.24,.76,.72],amber:[.89,.59,.3]} as Record<string,number[]>)[tint]??[.46,.75,.9];
      r.gl.uniform3f(r.gl.getUniformLocation(r.program,"trackTint"),tc[0],tc[1],tc[2]);
      r.gl.uniform1f(r.gl.getUniformLocation(r.program,"trackTintStrength"),tint==="ice"?0:.42);
      const rgb=(hex:string)=>{const match=/^#([0-9a-f]{6})$/i.exec(hex);if(!match)return [0.3,0.7,1];const n=parseInt(match[1],16);return [(n>>16&255)/255,(n>>8&255)/255,(n&255)/255]};
      for(const [index,name] of ["trackTintA","trackTintB","trackTintC"].entries()){const c=tintColors?rgb(tintColors[index]):tc;r.gl.uniform3f(r.gl.getUniformLocation(r.program,name),c[0],c[1],c[2])}
      for(const [index,name] of ["fillColorA","fillColorB","fillColorC"].entries()){const c=rgb(colors[index]??"#80cfff");r.gl.uniform3f(r.gl.getUniformLocation(r.program,name),c[0],c[1],c[2])}
      r.gl.uniform1f(r.gl.getUniformLocation(r.program,"unknown"),0);
      r.gl.uniform1f(r.gl.getUniformLocation(r.program,"seconds"),0);
      r.gl.drawArrays(r.gl.TRIANGLES,0,3);ctx.clearRect(0,0,w,h);ctx.drawImage(r.canvas,0,0);setFailed(false);
    };
    const observer=new ResizeObserver(draw);observer.observe(target);draw();
    return()=>observer.disconnect();
  },[percent,finish,tint,colors,tintColors]);
  return <><canvas className="cg-frost-ribbon" ref={ref} aria-hidden="true"/>{failed&&<span className="cg-ribbon-fallback" style={{width:`${percent}%`,background:fallback}}/>}</>;
}
