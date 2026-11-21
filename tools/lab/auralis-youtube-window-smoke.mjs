// Windows regression: real WebView2 commands must not freeze the application's UI.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {mkdir,readdir} from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
const {chromium}=createRequire(import.meta.url)('../../glass-ui/node_modules/playwright-core');
assert.equal(process.platform,'win32');
const root=path.join(process.env.RUNNER_TEMP,'auralis-youtube-smoke'),install=path.join(root,'install');
await mkdir(root,{recursive:true});
const bundle=path.resolve('glass-ui/src-tauri/target/release/bundle/nsis');
const setups=(await readdir(bundle)).filter(f=>/^Auralis Download Manager_.*_x64-setup\.exe$/i.test(f));
assert.equal(setups.length,1,'Expected one Auralis installer');
const setup=path.join(bundle,setups[0]);
const installed=spawnSync(setup,['/S',`/D=${install}`],{encoding:'utf8',timeout:180000});
assert.equal(installed.status,0,'Could not install Auralis for the sign-in regression');
const exe=path.join(install,'auralis-download-manager.exe');
const socket=net.createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const port=socket.address().port;await new Promise(r=>socket.close(r));
const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,message,timeout=90000){const end=Date.now()+timeout;let last;while(Date.now()<end){try{const v=await fn();if(v)return v}catch(e){last=e}await wait(300)}throw Error(message+(last?': '+last.message:''))}
const timed=(promise,label)=>{let timer;return Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error(label+' timed out; the UI may be blocked')),20000)})]).finally(()=>clearTimeout(timer))};
let app,browser;
try {
 app=spawn(exe,[],{env:{...process.env,MDM_DATA_DIR:path.join(root,'data'),MDM_REMOTE:'off',GLASS_TEST_CDP_PORT:String(port),WEBVIEW2_USER_DATA_FOLDER:path.join(root,'webview'),WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:`--remote-debugging-port=${port} --remote-debugging-address=127.0.0.1 --remote-allow-origins=*`},stdio:'ignore'});
 browser=await until(async()=>{if(app.exitCode!==null)throw Error('Auralis exited: '+app.exitCode);try{return await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:2000})}catch{return null}},'Auralis WebView did not start');
 const main=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&!p.url().includes('?')),'Main window not found');
 const invoke=(command,args={})=>timed(main.evaluate(([command,args])=>window.__TAURI_INTERNALS__.invoke(command,args),[command,args]),command);
 await until(()=>main.locator('.cg-main-body').count(),'Main window did not render');
 await invoke('open_youtube_sign_in');
 await timed(main.evaluate(()=>document.querySelector('.cg-main-body')!==null),'Main window after sign-in opened');
 await invoke('open_youtube_sign_in');
 // An unsigned-in test profile may return an error; it must return promptly, never freeze.
 const lookup=await invoke('video_tool',{action:'lookup',value:'https://www.youtube.com/watch?v=example',choice:null,subs:null,cookies:null,cookieBrowser:null,appSession:true}).then(()=>true,()=>true);
 assert(lookup);
 await timed(main.evaluate(()=>document.querySelector('.cg-main-body')!==null),'Main window after cookie lookup');
 console.log('PASS: opening and reopening sign-in and checking its cookies did not block the main window.');
} finally {
 if(browser)await browser.close().catch(()=>{});
 if(app&&!app.killed)app.kill();
 spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',"Get-Process -Name 'auralis-download-manager','mdm-legacy' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($env:AURALIS_SMOKE_INSTALL,[System.StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force -ErrorAction SilentlyContinue"],{env:{...process.env,AURALIS_SMOKE_INSTALL:install},timeout:15000});
}
