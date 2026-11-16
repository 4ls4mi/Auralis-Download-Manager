import {useEffect, useRef} from 'react';

// A decorative GPU layer only: it never samples the screen or receives download data.
// Windows supplies the actual backdrop separately. Failure leaves the CSS material in place.
const vertex = `attribute vec2 p; varying vec2 uv; void main(){uv=p*.5+.5;gl_Position=vec4(p,0.,1.);}`;
const fragment = `precision mediump float;
varying vec2 uv; uniform vec2 resolution; uniform float style; uniform float hue; uniform float strength; uniform float lightMode;
vec3 hsv(float h){vec3 k=mod(vec3(0.,4.,2.)+h*6.,6.);return .68+.32*clamp(abs(k-3.)-1.,0.,1.);}
float line(float y,float center,float width){return exp(-pow((y-center)/width,2.));}
void main(){
 vec2 p=uv; p.y=1.-p.y; float aspect=resolution.x/max(resolution.y,1.);
 float glow=0.; float facets=0.;
 if(style<.5){float wave=.13+.035*sin(p.x*8.5)+.012*sin(p.x*20.);glow=line(p.y,wave,.009)*.65+line(p.y,wave+.018,.026)*.23;glow+=line(p.y,.88+.025*sin(p.x*8.),.012)*.32;}
 else if(style<1.5){float cut=p.x*aspect+p.y*.95;facets=step(.88,fract(cut*2.5))*.16+line(fract(cut*2.5),.88,.025)*.50;}
 else if(style<2.5){glow=line(p.y,.055+.10*p.x*p.x,.016)*.48+exp(-p.y*12.)*.18;}
 else if(style<3.5){float t=p.x*aspect+p.y*1.3;facets=step(.92,fract(t*3.))*.20+line(fract(t*3.),.92,.023)*.54;glow=line(p.y,.90-p.x*.07,.015)*.28;}
 else if(style<4.5){glow=exp(-p.y*7.)*.24+line(p.y,.12+.035*sin(p.x*4.),.045)*.20;}
 else {glow=line(p.y,.09+.035*sin(p.x*6.),.02)*.25+exp(-p.y*10.)*.10;}
 vec3 tint=hsv(hue);vec3 white=mix(vec3(.68,.86,1.),vec3(1.),lightMode);float a=clamp((glow+facets)*(.38+strength*.55),0.,.44);vec3 c=mix(white,tint,.22);gl_FragColor=vec4(c,a);
}`;
const materialStyle=(name:string)=>name==='water-bubble'||name==='liquid-glass'?0:name==='ice-edge'||name==='diamond-facet'?1:name==='aero-gloss'?2:name==='prismatic-glass'||name==='holographic-film'?3:name==='frosted-layers'||name==='pearl-mist'?4:5;
export default function GlassRenderer({material,hue,strength,light}:{material:string;hue:number;strength:number;light:boolean}){
 const ref=useRef<HTMLCanvasElement>(null);
 useEffect(()=>{
  const canvas=ref.current;if(!canvas)return;
  const gl=canvas.getContext('webgl',{alpha:true,premultipliedAlpha:false,antialias:false});if(!gl)return;
  const compile=(type:number,source:string)=>{const shader=gl.createShader(type);if(!shader)return null;gl.shaderSource(shader,source);gl.compileShader(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS)){gl.deleteShader(shader);return null}return shader};
  const vs=compile(gl.VERTEX_SHADER,vertex),fs=compile(gl.FRAGMENT_SHADER,fragment);if(!vs||!fs){if(vs)gl.deleteShader(vs);if(fs)gl.deleteShader(fs);return}
  const program=gl.createProgram();if(!program){gl.deleteShader(vs);gl.deleteShader(fs);return}gl.attachShader(program,vs);gl.attachShader(program,fs);gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS)){gl.deleteProgram(program);gl.deleteShader(vs);gl.deleteShader(fs);return}
  const buffer=gl.createBuffer();if(!buffer){gl.deleteProgram(program);gl.deleteShader(vs);gl.deleteShader(fs);return}gl.useProgram(program);gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,1,1]),gl.STATIC_DRAW);const loc=gl.getAttribLocation(program,'p');gl.enableVertexAttribArray(loc);gl.vertexAttribPointer(loc,2,gl.FLOAT,false,0,0);
  const draw=()=>{const rect=canvas.getBoundingClientRect();if(!rect.width||!rect.height)return;const dpr=Math.min(window.devicePixelRatio||1,1.5);canvas.width=Math.max(1,Math.round(rect.width*dpr));canvas.height=Math.max(1,Math.round(rect.height*dpr));gl.viewport(0,0,canvas.width,canvas.height);gl.useProgram(program);gl.uniform2f(gl.getUniformLocation(program,'resolution'),canvas.width,canvas.height);gl.uniform1f(gl.getUniformLocation(program,'style'),materialStyle(material));gl.uniform1f(gl.getUniformLocation(program,'hue'),Math.max(0,Math.min(360,hue))/360);gl.uniform1f(gl.getUniformLocation(program,'strength'),Math.max(0,Math.min(65,strength))/65);gl.uniform1f(gl.getUniformLocation(program,'lightMode'),light?1:0);gl.drawArrays(gl.TRIANGLE_STRIP,0,4);canvas.dataset.renderer='webgl';};
  const observer=new ResizeObserver(draw);observer.observe(canvas);draw();return()=>{observer.disconnect();delete canvas.dataset.renderer;gl.deleteBuffer(buffer);gl.deleteProgram(program);gl.deleteShader(vs);gl.deleteShader(fs)};
 },[material,hue,strength,light]);
 return <canvas ref={ref} className="cg-material-renderer" aria-hidden="true"/>;
}
