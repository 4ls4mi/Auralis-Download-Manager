import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const browserPath=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('ribbon shader compiles with independent backdrop gradient colors',{skip:!browserPath||!existsSync(browserPath)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:browserPath,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{const page=await browser.newPage();await page.goto(server.resolvedUrls.local[0]);const result=await page.evaluate(async()=>{const {ribbonFragment}=await import('/src/frostedRibbonShader.ts');const gl=document.createElement('canvas').getContext('webgl');if(!gl)return 'WebGL unavailable';const shader=gl.createShader(gl.FRAGMENT_SHADER);gl.shaderSource(shader,ribbonFragment);gl.compileShader(shader);return gl.getShaderParameter(shader,gl.COMPILE_STATUS)?'ok':gl.getShaderInfoLog(shader)});assert.equal(result,'ok');}finally{await browser.close();await server.close()}
});
