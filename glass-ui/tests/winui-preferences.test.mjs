import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';
import {createServer} from 'vite';
const executable=process.env.AURALIS_TEST_BROWSER||(process.platform==='linux'?'/usr/bin/chromium':'');
test('isolated connection preferences load and save through the native bridge',{skip:!executable||!existsSync(executable)},async()=>{
 const server=await createServer({configFile:false,root:fileURLToPath(new URL('..',import.meta.url)),server:{host:'127.0.0.1',port:0},logLevel:'silent'});await server.listen();
 const browser=await chromium.launch({headless:true,executablePath:executable,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{let listener,enabled=false,proxy='',passwordSaved=false;window.requests=[];window.chrome={webview:{addEventListener:(_name,fn)=>{listener=fn},postMessage:message=>{
   window.requests.push(message);let value={applied:true};
   if(message.command==='preferences')value={fields:[{key:'many_connections',label:'Allow more than 32 connections',section:'Connection',kind:'boolean',value:enabled},{key:'proxy_host',label:'Proxy server',section:'Connection',kind:'text',value:proxy},{key:'proxy_pass',label:'Proxy password',section:'Connection',kind:'password',value:'',saved:passwordSaved}]};
   else if(message.command==='update_preference'){if(message.key==='many_connections')enabled=message.value;if(message.key==='proxy_host')proxy=message.value;if(message.key==='proxy_pass')passwordSaved=message.clear?false:Boolean(message.value)||passwordSaved;value={ok:true}}
   else if(message.command==='glass_settings')value={net_adapter:''};
   else if(message.command==='network_adapters')value={adapters:[{name:'Test VPN',address:'127.0.0.1'}]};
   else if(message.command==='update_glass_setting')value={saved:true};
   else if(message.command==='dashboard_snapshot')value={downloads:[],queues:[],categories:[],speed:0};
   else if(message.command==='app_version')value='0.3.48';
   else if(message.command==='window_is_maximized')value=false;
   else if(message.command==='window_current_monitor')value=null;
   else if(message.command==='window_outer_position')value={x:0,y:0};
   else if(message.command==='window_outer_size')value={width:960,height:690};
   queueMicrotask(()=>listener({data:{id:message.id,ok:true,value}}));
  }}}});
  await page.addInitScript({content:readFileSync(new URL('../../winui-shell/webview/sandbox-compat.js',import.meta.url),'utf8')});
  await page.goto(server.resolvedUrls.local[0]+'?settings=1&tab=Connection');
  await page.getByLabel('Preferred network adapter').selectOption('Test VPN');
  await page.waitForFunction(()=>window.requests.some(m=>m.command==='update_glass_setting' && m.key==='net_adapter' && m.value==='Test VPN'));
  await page.getByRole('button',{name:'All settings',exact:true}).click();
  const input=page.getByLabel('Enabled',{exact:true});await input.check();
  await page.getByRole('button',{name:'Save preference'}).click();
  await page.waitForFunction(()=>window.requests.some(m=>m.command==='update_preference' && m.key==='many_connections' && m.value===true));
  await page.getByRole('status').filter({hasText:'Saved.'}).waitFor();
  assert.equal(await input.isChecked(),true);
  await page.getByRole('button',{name:'Proxy password',exact:true}).click();
  await page.getByLabel('Password',{exact:true}).fill('example-secret');
  await page.getByRole('button',{name:'Save preference'}).click();
  await page.getByText('A password is saved. Leave blank to keep it.').waitFor();
  await page.getByLabel('Clear saved password').check();
  await page.getByRole('button',{name:'Save preference'}).click();
  await page.waitForFunction(()=>window.requests.some(m=>m.command==='update_preference' && m.key==='proxy_pass' && m.clear===true && m.value===''));
  await page.getByRole('button',{name:'Proxy server',exact:true}).click();
  await page.getByLabel('Proxy server',{exact:true}).fill('proxy.example.test');
  await page.getByRole('button',{name:'Save preference'}).click();
  await page.waitForFunction(()=>window.requests.some(m=>m.command==='update_preference' && m.key==='proxy_host' && m.value==='proxy.example.test'));
  await page.getByRole('status').filter({hasText:'Saved.'}).waitFor();
 }finally{await browser.close();await server.close()}
});
