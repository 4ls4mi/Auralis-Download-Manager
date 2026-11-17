/** GPU backdrop compositor. The caller owns and explicitly starts/stops capture.
 * Source pixels stay in GPU memory and are never saved or transmitted here. */
export type CaptureRect = {x:number; y:number; width:number; height:number};
export type RefractionStyle = 'water'|'crystal'|'frosted';
const vertex=`attribute vec2 position; varying vec2 uv;
void main(){uv=position*.5+.5;gl_Position=vec4(position,0.,1.);}`;
const fragment=`precision mediump float;
varying vec2 uv; uniform sampler2D backdrop; uniform vec4 crop;
uniform vec2 sourceSize; uniform float style; uniform float amount;
void main(){
 vec2 screenUv=vec2(crop.x+uv.x*crop.z,crop.y+(1.-uv.y)*crop.w);
 vec2 displacement;
 if(style<.5){
   displacement=vec2(sin(uv.y*12.+uv.x*4.),cos(uv.x*11.-uv.y*3.));
 }else if(style<1.5){
   vec2 facet=floor(uv*vec2(9.,6.));
   displacement=vec2(mod(facet.x+facet.y,2.)*2.-1.,mod(facet.x*2.+facet.y,3.)-1.);
 }else{displacement=vec2(0.);}
 vec2 pixel=1./sourceSize;
 vec2 sampleUv=clamp(screenUv+displacement*amount*pixel,pixel,vec2(1.)-pixel);
 vec4 result=texture2D(backdrop,sampleUv);
 if(style>1.5){
   vec2 blur=pixel*amount*.45;
   result=(result*2.+texture2D(backdrop,clamp(sampleUv+vec2(blur.x,0.),pixel,vec2(1.)-pixel))
     +texture2D(backdrop,clamp(sampleUv-vec2(blur.x,0.),pixel,vec2(1.)-pixel))
     +texture2D(backdrop,clamp(sampleUv+vec2(0.,blur.y),pixel,vec2(1.)-pixel))
     +texture2D(backdrop,clamp(sampleUv-vec2(0.,blur.y),pixel,vec2(1.)-pixel)))/6.;
 }
 gl_FragColor=vec4(result.rgb,1.);
}`;
function shader(gl:WebGLRenderingContext,type:number,source:string):WebGLShader{
 const item=gl.createShader(type);if(!item)throw Error('Cannot create WebGL shader');
 gl.shaderSource(item,source);gl.compileShader(item);
 if(!gl.getShaderParameter(item,gl.COMPILE_STATUS)){const error=gl.getShaderInfoLog(item);gl.deleteShader(item);throw Error(`Backdrop shader: ${error}`)}
 return item;
}
export class DesktopRefraction {
 private gl:WebGLRenderingContext;private program:WebGLProgram;private texture:WebGLTexture;private buffer:WebGLBuffer;
 constructor(private canvas:HTMLCanvasElement){
  const gl=canvas.getContext('webgl',{alpha:false,premultipliedAlpha:false,antialias:false});if(!gl)throw Error('WebGL is unavailable');
  const vs=shader(gl,gl.VERTEX_SHADER,vertex),fs=shader(gl,gl.FRAGMENT_SHADER,fragment),program=gl.createProgram();
  if(!program){gl.deleteShader(vs);gl.deleteShader(fs);throw Error('Cannot create backdrop program')}
  gl.attachShader(program,vs);gl.attachShader(program,fs);gl.linkProgram(program);gl.deleteShader(vs);gl.deleteShader(fs);
  if(!gl.getProgramParameter(program,gl.LINK_STATUS)){const e=gl.getProgramInfoLog(program);gl.deleteProgram(program);throw Error(`Backdrop program: ${e}`)}
  const texture=gl.createTexture(),buffer=gl.createBuffer();if(!texture||!buffer){if(texture)gl.deleteTexture(texture);if(buffer)gl.deleteBuffer(buffer);gl.deleteProgram(program);throw Error('Cannot allocate backdrop resources')}
  this.gl=gl;this.program=program;this.texture=texture;this.buffer=buffer;
  gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,1,1]),gl.STATIC_DRAW);
  gl.bindTexture(gl.TEXTURE_2D,texture);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
 }
 draw(source:TexImageSource,sourceWidth:number,sourceHeight:number,rect:CaptureRect,style:RefractionStyle,amount:number){
  if(sourceWidth<=0||sourceHeight<=0||rect.width<=0||rect.height<=0||rect.x<0||rect.y<0||rect.x+rect.width>sourceWidth||rect.y+rect.height>sourceHeight)throw Error('Backdrop capture does not cover this window');
  const gl=this.gl;if(gl.isContextLost())throw Error('Backdrop graphics context was lost');
  gl.viewport(0,0,this.canvas.width,this.canvas.height);gl.useProgram(this.program);
  gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);const position=gl.getAttribLocation(this.program,'position');gl.enableVertexAttribArray(position);gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);
  gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,this.texture);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,0);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,source);
  gl.uniform1i(gl.getUniformLocation(this.program,'backdrop'),0);gl.uniform4f(gl.getUniformLocation(this.program,'crop'),rect.x/sourceWidth,rect.y/sourceHeight,rect.width/sourceWidth,rect.height/sourceHeight);
  gl.uniform2f(gl.getUniformLocation(this.program,'sourceSize'),sourceWidth,sourceHeight);gl.uniform1f(gl.getUniformLocation(this.program,'style'),style==='water'?0:style==='crystal'?1:2);gl.uniform1f(gl.getUniformLocation(this.program,'amount'),Math.max(0,Math.min(30,amount)));
  gl.drawArrays(gl.TRIANGLE_STRIP,0,4);
 }
 dispose(){this.gl.deleteBuffer(this.buffer);this.gl.deleteTexture(this.texture);this.gl.deleteProgram(this.program)}
}
