// This page runs in the extension, never in a website. Cookie values only reach the local file.
const ext=globalThis.browser??globalThis.chrome;
const status=document.getElementById('status');
const retry=document.getElementById('start');
const login='https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2F';
const robots='https://www.youtube.com/robots.txt';
const auth=new Set(['SID','SAPISID','__Secure-1PSID','__Secure-3PSID','__Secure-1PAPISID','__Secure-3PAPISID']);
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let busy=false;
function encode(cookies){
 const clean=s=>String(s??'').replace(/[\t\r\n]/g,'');
 return '# Netscape HTTP Cookie File\n# This file contains a private sign-in session.\n'+cookies.map(c=>{
  const domain=clean(c.domain), prefix=c.httpOnly?'#HttpOnly_':'';
  return [prefix+domain,c.hostOnly?'FALSE':'TRUE',clean(c.path||'/'),c.secure?'TRUE':'FALSE',String(Math.floor(c.expirationDate||0)),clean(c.name),clean(c.value)].join('\t');
 }).join('\n')+'\n';
}
async function start(){
 if(busy)return;busy=true;retry.hidden=true;let created;
 try{
  const allowed=await ext.extension.isAllowedIncognitoAccess();
  if(!allowed)throw Error('Allow Auralis in InPrivate/Incognito in your browser’s extension details, then return here and choose Try again.');
  const windows=await ext.windows.getAll();
  if(windows.some(w=>w.incognito))throw Error('Close existing private windows first, then choose Try again. This keeps the new YouTube session separate.');
  created=await ext.windows.create({url:login,incognito:true,focused:true});
  const tab=created.tabs?.[0];if(!tab?.id)throw Error('The browser did not open the private sign-in tab.');
  const storeId=tab.cookieStoreId||(globalThis.browser?'firefox-private':'1');
  status.textContent='Sign in to YouTube in the private window. Auralis will continue automatically after YouTube opens.';
  let signedIn=false;
  for(let i=0;i<300;i++){
   await sleep(1000);
   let current;try{current=await ext.tabs.get(tab.id)}catch{throw Error('The private sign-in window was closed before export.')}
   let u;try{u=new URL(current.url||'')}catch{continue}
   if(u.hostname!=='youtube.com'&&!u.hostname.endsWith('.youtube.com'))continue;
   const cookies=await ext.cookies.getAll({url:'https://www.youtube.com/',storeId});
   if(cookies.some(c=>auth.has(c.name)&&c.value)){signedIn=true;break}
  }
  if(!signedIn)throw Error('Sign-in was not detected. Make sure your account can open YouTube, then try again.');
  status.textContent='Sign-in detected. Preparing your cookie file…';
  await ext.tabs.update(tab.id,{url:robots});
  let ready=false;
  for(let i=0;i<30;i++){
   await sleep(500);let current;try{current=await ext.tabs.get(tab.id)}catch{throw Error('The private window was closed before export.')}
   if(current.url===robots&&current.status==='complete'){ready=true;break}
  }
  if(!ready)throw Error('YouTube did not finish opening the export page. Try again.');
  const cookies=await ext.cookies.getAll({domain:'youtube.com',storeId});
  const youtube=cookies.filter(c=>{const d=String(c.domain||'').replace(/^\./,'').toLowerCase();return d==='youtube.com'||d.endsWith('.youtube.com')});
  if(!youtube.some(c=>auth.has(c.name)&&c.value))throw Error('No YouTube sign-in cookies were found in the private session.');
  const blob=new Blob([encode(youtube)],{type:'text/plain'}),url=URL.createObjectURL(blob);
  const a=document.createElement('a');a.href=url;a.download='auralis-youtube-cookies.txt';document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
  // Never close tabs the user added to the window during sign-in.
  const win=await ext.windows.get(created.id,{populate:true}).catch(()=>null);
  if(win?.tabs?.length===1&&win.tabs[0].id===tab.id)await ext.windows.remove(created.id);
  status.textContent='Cookie export started. Select the downloaded auralis-youtube-cookies.txt file in Auralis or its video menu. Keep the file private.';
 }catch(e){status.textContent=String(e?.message||e);retry.hidden=false}
 finally{busy=false}
}
retry.addEventListener('click',()=>void start());
void start();
