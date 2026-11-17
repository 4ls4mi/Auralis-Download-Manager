// Windows x64 only. Builds installable 0.3.0 with the real updater, installs it in an
// isolated runner folder, and updates through the actual public 0.3.1 release and UI.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {mkdir,readFile,readdir,writeFile} from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
const {chromium}=createRequire(import.meta.url)('../../glass-ui/node_modules/playwright-core');
assert.equal(process.platform,'win32');assert.equal(process.arch,'x64');
const temp=process.env.RUNNER_TEMP;assert(temp,'RUNNER_TEMP is required');
const root=path.join(temp,'glass-updater-e2e'),install=path.join(root,'install'),data=path.join(root,'data'),proof=path.join(root,'proof');
await mkdir(data,{recursive:true});await mkdir(proof,{recursive:true});
const setupDir=path.resolve('glass-ui/src-tauri/target/release/bundle/nsis');const setups=(await readdir(setupDir)).filter(x=>x.endsWith('.exe'));assert.equal(setups.length,1);
const setup=path.join(setupDir,setups[0]),exe=path.join(install,'mister-hybrid-glass.exe');
const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,message,timeout=90000){const start=Date.now();let last;while(Date.now()-start<timeout){try{const r=await fn();if(r)return r}catch(e){last=e}await wait(300)}throw Error(message+(last?': '+last.message:''))}
function powershell(code,extra={}){return spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',code],{encoding:'utf8',timeout:15000,env:{...process.env,MHG_TEST_EXE:exe,MHG_TEST_ROOT:install,...extra}})}
let browser,old,passed=false;
try{
 const initial=spawnSync(setup,['/S',`/D=${install}`],{encoding:'utf8',timeout:180000});assert.equal(initial.status,0,'Isolated old-version install failed: '+(initial.stderr||initial.error?.message||''));
 const portServer=net.createServer();await new Promise(r=>portServer.listen(0,'127.0.0.1',r));const port=portServer.address().port;await new Promise(r=>portServer.close(r));
 old=spawn(exe,[],{env:{...process.env,MDM_DATA_DIR:data,MDM_REMOTE:'off',GLASS_TEST_CDP_PORT:String(port),WEBVIEW2_USER_DATA_FOLDER:path.join(root,'webview'),WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:`--remote-debugging-port=${port} --remote-debugging-address=127.0.0.1 --remote-allow-origins=*`},stdio:'ignore'});
 browser=await until(async()=>{if(old.exitCode!==null)throw Error('Initial app exited: '+old.exitCode);try{return await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:3000})}catch{return null}},'Initial WebView did not appear');
 const main=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.url().includes('?')),'Main window not found');
 await main.locator('.cg-toolbar').getByRole('button',{name:'Settings',exact:true}).click();
 const settings=await until(()=>browser.contexts().flatMap(c=>c.pages()).find(p=>!p.isClosed()&&p.url().includes('settings=')),'Settings window not found');
 await settings.getByRole('button',{name:'Advanced',exact:true}).click();await settings.getByRole('button',{name:'Updates',exact:true}).click();
 await settings.getByText('Mister Hybrid Glass 0.3.1 is available.',{exact:true}).waitFor({timeout:90000});
 await settings.getByRole('button',{name:'Show changelog',exact:true}).click();assert((await settings.locator('pre').innerText()).includes('Changes since 0.3.0'));
 await settings.screenshot({path:path.join(proof,'update-changelog.png')});
 await settings.getByRole('button',{name:'Download update',exact:true}).click();
 await settings.getByText('Update downloaded and verified. Restart to install it.',{exact:true}).waitFor({timeout:240000});
 await settings.screenshot({path:path.join(proof,'update-ready.png')});
 try{await settings.getByRole('button',{name:'Restart and install',exact:true}).click({timeout:15000})}catch(e){await wait(2000);if(old.exitCode===null)throw e}
 await until(()=>old.exitCode!==null,'The app did not exit to install the update',45000);
 await until(()=>{const p=powershell("if ((Test-Path $env:MHG_TEST_EXE) -and ((Get-Item $env:MHG_TEST_EXE).VersionInfo.ProductVersion -like '0.3.1*') -and (Get-Process -Name 'mister-hybrid-glass' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $env:MHG_TEST_EXE })) { exit 0 } else { exit 1 }");return p.status===0},'The public update did not install and restart the app',180000);
 await until(async()=>{const ep=JSON.parse(await readFile(path.join(data,'ipc.json'),'utf8'));return await new Promise(resolve=>{let reply='';const socket=net.connect({host:'127.0.0.1',port:ep.port},()=>socket.write(JSON.stringify({token:ep.token,query:'glass-backend'})+'\n'));socket.setTimeout(3000,()=>socket.destroy());socket.on('data',b=>{reply+=b.toString();if(reply.includes('\n')){socket.end();try{const answer=JSON.parse(reply.split('\n')[0]);resolve(answer.headless&&answer.glass)}catch{resolve(false)}}});socket.on('error',()=>resolve(false));socket.on('close',()=>resolve(false))})},'The original backend did not restart',45000);
 passed=true;await writeFile(path.join(proof,'results.json'),JSON.stringify({status:'passed',flow:'real public 0.3.1 release: check, changelog, download, verify, restart and install'},null,2));
 console.log('PASS: real in-app update to public 0.3.1 completed and restarted');
}catch(e){
 if(browser)for(const [i,p] of browser.contexts().flatMap(c=>c.pages()).entries())if(!p.isClosed())await p.screenshot({path:path.join(proof,`failure-${i}.png`)}).catch(()=>{});
 await writeFile(path.join(proof,'results.json'),JSON.stringify({status:'failed',error:String(e?.stack||e)},null,2));console.error(e);process.exitCode=1;
}finally{
 if(browser)await browser.close().catch(()=>{});
 powershell("Get-Process -Name 'mister-hybrid-glass','mdm-legacy' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($env:MHG_TEST_ROOT,[System.StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force -ErrorAction SilentlyContinue");
 const uninstall=path.join(install,'uninstall.exe');spawnSync(uninstall,['/S'],{timeout:30000,stdio:'ignore'});
 if(!passed)console.error('See the updater proof artifact for diagnostic screenshots.');
}
