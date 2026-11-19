import {liquidMaterialFragment} from './liquidMaterialShader';
import {frostVertex} from './frostedLayersShader';
type Renderer={canvas:HTMLCanvasElement;gl:WebGLRenderingContext;program:WebGLProgram};
let renderer:Renderer|null|undefined;
function getRenderer():Renderer|null{
 if(renderer!==undefined&&!renderer?.gl.isContextLost())return renderer;
 try{const canvas=document.createElement('canvas'),gl=canvas.getContext('webgl',{alpha:true,premultipliedAlpha:false,preserveDrawingBuffer:true,depth:false});if(!gl)throw Error('WebGL unavailable');
  const compile=(type:number,src:string)=>{const shader=gl.createShader(type);if(!shader)throw Error('Shader unavailable');gl.shaderSource(shader,src);gl.compileShader(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(shader)||'Shader failed');return shader};
  const vs=compile(gl.VERTEX_SHADER,frostVertex),fs=compile(gl.FRAGMENT_SHADER,liquidMaterialFragment),program=gl.createProgram();if(!program)throw Error('Program unavailable');gl.attachShader(program,vs);gl.attachShader(program,fs);gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(program)||'Link failed');gl.deleteShader(vs);gl.deleteShader(fs);gl.useProgram(program);const buffer=gl.createBuffer();if(!buffer)throw Error('Buffer unavailable');gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);const position=gl.getAttribLocation(program,'position');gl.enableVertexAttribArray(position);gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);renderer={canvas,gl,program};
 }catch{renderer=null}return renderer;
}
function rgb(hex:string){const match=/^#([0-9a-f]{6})$/i.exec(hex);if(!match)return [.1,.6,1];const n=parseInt(match[1],16);return [(n>>16&255)/255,(n>>8&255)/255,(n&255)/255]}
/** One shared context avoids exhausting WebView's limit in long download lists. */
export function renderLiquidGpu(width:number,height:number,seconds:number,material:string,colors:string[]):HTMLCanvasElement|null{
 const r=getRenderer();if(!r)return null;
 try{const w=Math.max(1,Math.min(2048,Math.round(width))),h=Math.max(1,Math.min(256,Math.round(height)));if(r.canvas.width!==w||r.canvas.height!==h){r.canvas.width=w;r.canvas.height=h}const {gl,program}=r;gl.viewport(0,0,w,h);gl.useProgram(program);gl.uniform2f(gl.getUniformLocation(program,'viewport'),w,h);gl.uniform1f(gl.getUniformLocation(program,'seconds'),seconds);gl.uniform1f(gl.getUniformLocation(program,'material'),material==='liquid-crystal'?1:material==='liquid-aero'?2:0);for(const [i,name] of ['colorA','colorB','colorC'].entries()){const c=rgb(colors[i]||'#4088ff');gl.uniform3f(gl.getUniformLocation(program,name),c[0],c[1],c[2])}gl.drawArrays(gl.TRIANGLES,0,3);return r.canvas}catch{return null}
}
