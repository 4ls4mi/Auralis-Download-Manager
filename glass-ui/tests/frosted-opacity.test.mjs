import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('frosted shader opacity changes rendered glass alpha',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{const page=await browser.newPage();await page.goto(server.resolvedUrls.local[0]);const values=await page.evaluate(async()=>{
 const {frostVertex,frostFragment}=await import('/src/frostedLayersShader.ts');const canvas=document.createElement('canvas');canvas.width=100;canvas.height=100;const gl=canvas.getContext('webgl',{preserveDrawingBuffer:true});
 const compile=(type,src)=>{const sh=gl.createShader(type);gl.shaderSource(sh,src);gl.compileShader(sh);if(!gl.getShaderParameter(sh,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(sh));return sh};
 const program=gl.createProgram();gl.attachShader(program,compile(gl.VERTEX_SHADER,frostVertex));gl.attachShader(program,compile(gl.FRAGMENT_SHADER,frostFragment));gl.linkProgram(program);gl.useProgram(program);const b=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);const pos=gl.getAttribLocation(program,'position');gl.enableVertexAttribArray(pos);gl.vertexAttribPointer(pos,2,gl.FLOAT,false,0,0);gl.viewport(0,0,100,100);gl.uniform2f(gl.getUniformLocation(program,'viewport'),100,100);
 return [.45,1].map(opacity=>{gl.uniform1f(gl.getUniformLocation(program,'glassOpacity'),opacity);gl.drawArrays(gl.TRIANGLES,0,3);const pixels=new Uint8Array(4);gl.readPixels(50,50,1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixels);return pixels[3]});
 });assert(values[0]>0&&values[1]>values[0]*1.8,JSON.stringify(values));}finally{await browser.close();await server.close()}
});
