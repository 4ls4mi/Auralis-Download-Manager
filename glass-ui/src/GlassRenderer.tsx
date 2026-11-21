import {useEffect, useRef} from 'react';

// A decorative GPU layer only: it never samples the screen or receives download data.
// Windows supplies the actual backdrop separately. Failure leaves the CSS material in place.
const vertex = `attribute vec2 p; varying vec2 uv; void main(){uv=p*.5+.5;gl_Position=vec4(p,0.,1.);}`;
const fragment = `precision mediump float;
varying vec2 uv; uniform vec2 resolution; uniform float style; uniform float hue; uniform float strength; uniform float lightMode;
vec3 hsv(float h){vec3 k=mod(vec3(0.,4.,2.)+h*6.,6.);return .68+.32*clamp(abs(k-3.)-1.,0.,1.);}
float band(float x,float c,float w){return exp(-pow((x-c)/w,2.));}
void main(){
 vec2 p=vec2(uv.x,1.-uv.y);float aspect=resolution.x/max(resolution.y,1.);float border=min(min(p.x,1.-p.x)*aspect,min(p.y,1.-p.y));float g=0.;float f=0.;float shift=0.;
 if(style<.5){float d=p.x*aspect+p.y;f=step(.8,fract(d*2.1))*.19;g=band(fract(d*2.1),.8,.02)*.48+band(border,.012,.009)*.42;}
 else if(style<1.5){g=band(border,.028,.006)*.26+band(p.y,.12,.035)*.10;f=step(.60,p.x)*step(p.y,.22)*.08;}
 else if(style<2.5){g=exp(-length((p-vec2(.25,-.12))*vec2(1.,2.))*3.)*.30+exp(-length((p-vec2(.9,.4))*2.)*3.)*.16;}
 else if(style<3.5){float arc=.06+.13*pow(p.x-.48,2.);g=band(p.y,arc,.022)*.40+exp(-p.y*9.)*.17+band(border,.012,.01)*.20;}
 else if(style<4.5){float d=p.x*aspect+p.y*1.3;f=step(.88,fract(d*2.5))*.13;g=band(fract(d*2.5),.88,.025)*.47+band(border,.012,.008)*.40;shift=p.x*.8+p.y*.3;}
 else if(style<5.5){float wave=.10+.03*sin(p.x*6.5);g=band(p.y,wave,.018)*.40+band(p.y,.88+.03*sin(p.x*7.),.018)*.26+band(border,.013,.009)*.22;}
 else if(style<6.5){g=band(border,.008,.006)*.32+exp(-p.y*18.)*.12;}
 else if(style<7.5){float d=p.x*aspect+p.y;float e=p.x*aspect-p.y;g=(band(fract(d*2.6),.87,.023)+band(fract(e*2.6),.87,.023))*.24+band(border,.015,.009)*.45;f=step(.9,fract(d*2.6))*.12;}
 else if(style<8.5){g=band(p.y+p.x*.35,.5,.22)*.25+band(border,.012,.01)*.25;shift=p.x+p.y*.45;}
 else if(style<9.5){g=exp(-length((p-vec2(.2,.05))*vec2(1.3,3.))*2.)*.24+band(border,.018,.018)*.13;shift=.16;}
 else if(style<10.5){g=band(p.y,.24+.08*sin(p.x*5.),.09)*.25+band(p.y,.50+.09*sin(p.x*4.+1.),.08)*.18;shift=p.x*.5;}
 else if(style<11.5){g=band(border,.015,.01)*.22;f=step(.8,fract((p.x*aspect+p.y)*90.))*.045;}
 else{float wave=.10+.035*sin(p.x*8.5)+.012*sin(p.x*20.);g=band(p.y,wave,.009)*.55+band(p.y,wave+.018,.026)*.20+band(p.y,.88+.025*sin(p.x*8.),.012)*.32+band(border,.015,.01)*.30;}
 vec3 tint=hsv(fract(hue+shift*.3));vec3 white=mix(vec3(.68,.86,1.),vec3(1.),lightMode);float alpha=clamp((g+f)*(.35+strength*.48),0.,.38);gl_FragColor=vec4(mix(white,tint,.30),alpha);
}`;
// Every material uses its own GPU light model.
const materialStyles=['ice-edge','smoked-crystal','frosted-layers','aero-gloss','prismatic-glass','liquid-glass','obsidian-glass','diamond-facet','holographic-film','pearl-mist','aurora-veil','brushed-glass','water-bubble'];
const materialStyle=(name:string)=>{const id=materialStyles.indexOf(name);return id<0?0:id};
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
