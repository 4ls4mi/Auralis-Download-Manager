// Auralis controls on YouTube cards work even before hover previews create a <video>.
(() => {
  const ext = globalThis.browser ?? globalThis.chrome;
  const seen = new WeakMap();
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  async function lookup(url, menu, cookieMode, cookieFile) {
    menu.replaceChildren();
    const status = document.createElement('div'); status.className='lookup-status'; status.textContent = 'Looking up qualities…'; menu.append(status);
    try {
      let r = await ext.runtime.sendMessage({type:'video-lookup',url,thumbnail:true,cookieMode,cookieFile,includeGoogleCookies:true});
      let answer = r?.lookup;
      for (let n=0; answer?.state==='pending' && n<60; n++) {
        await delay(1000);
        r = await ext.runtime.sendMessage({type:'video-poll',token:answer.token});
        answer = {...r?.lookup,token:r?.lookup?.token || answer.token};
      }
      if (answer?.state!=='ready' || !answer.token || !answer.choices?.length) {
        status.textContent = answer?.message || 'Could not fetch qualities. Check Auralis and yt-dlp.'; return;
      }
      status.textContent = answer.title || 'Choose a quality';
      const subsSection = document.createElement('section'); const subsTitle=document.createElement('strong'); subsTitle.textContent='Subtitles'; subsSection.append(subsTitle);
      const subs = document.createElement('select'); subs.setAttribute('aria-label','Subtitles');
      const addOption=(value,label)=>{const option=document.createElement('option');option.value=value;option.textContent=label;subs.append(option)};
      addOption('none','No subtitles');
      for (const [kind,tracks] of [['manual',answer.subtitles||[]],['auto',answer.automatic_subtitles||[]]]) {
        if(tracks.length)addOption(`${kind}:all`,kind==='auto'?'All automatic captions':'All subtitles');
        for(const track of tracks)addOption(`${kind}:${track.code}`,`${track.name || track.code} (${track.code})${kind==='auto'?' · automatic':''}`);
      }
      subs.hidden=true;subsSection.append(subs);
      const captionInfo=document.createElement('small');captionInfo.textContent=`${(answer.subtitles||[]).length} subtitle languages · ${(answer.automatic_subtitles||[]).length} automatic`;subsSection.append(captionInfo);
      const list=document.createElement('div');list.className='subtitle-list';
      const none=document.createElement('button');none.type='button';none.textContent='No subtitles';none.setAttribute('aria-pressed','true');none.addEventListener('click',event=>{event.preventDefault();event.stopPropagation();subs.value='none';list.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b===none)))});list.append(none);
      for(const [kind,tracks] of [['manual',answer.subtitles||[]],['auto',answer.automatic_subtitles||[]]]) for(const track of tracks){
        const option=document.createElement('button');option.type='button';option.textContent=`${track.name||track.code} (${track.code})${kind==='auto'?' · automatic':''}`;option.addEventListener('click',event=>{event.preventDefault();event.stopPropagation();subs.value=`${kind}:${track.code}`;list.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b===option)))});list.append(option);
      }
      if(list.childElementCount)subsSection.append(list);
      const videoSection=document.createElement('section'), audioSection=document.createElement('section');
      const videoTitle=document.createElement('strong'),audioTitle=document.createElement('strong');videoTitle.textContent='Video qualities';audioTitle.textContent='Audio qualities';videoSection.append(videoTitle);audioSection.append(audioTitle);
      let videoCount=0,audioCount=0;
      for (const [index,choice] of answer.choices.entries()) {
        const button=document.createElement('button'); button.type='button';
        button.className='quality'; button.textContent = `${choice.label || choice.ext || 'Download'}  ↓`;
        button.addEventListener('click', async event => {
          event.preventDefault(); event.stopPropagation(); button.disabled=true;
          try { const [kind,code]=subs.value.split(':'); const subtitles={langs:code?[code]:[],automatic:kind==='auto',embed:false}; const result=await ext.runtime.sendMessage({type:'video-pick',token:answer.token,choice:index,subs:subtitles});
            status.textContent=['started','queued','sent'].includes(result?.lookup?.state)?'Added to Auralis':'Could not start this download.';
          } catch { status.textContent='Could not reach Auralis.'; }
          button.disabled=false;
        });
        if(choice.audio){audioSection.append(button);audioCount++}else{videoSection.append(button);videoCount++}
      }
      videoTitle.textContent=`Video · ${videoCount}`;audioTitle.textContent=`Audio · ${audioCount}`;
      if(!videoCount){const empty=document.createElement('small');empty.textContent='No video qualities available';videoSection.append(empty)}
      if(!audioCount){const empty=document.createElement('small');empty.textContent='No audio qualities available';audioSection.append(empty)}
      menu.append(subsSection,videoSection,audioSection);
    } catch { status.textContent='Could not reach Auralis.'; }
  }
  function scan() {
    for (const anchor of document.querySelectorAll('a#thumbnail[href*="watch?v="]')) {
      const href = new URL(anchor.href, location.href); const id=href.searchParams.get('v');
      if (!id || !/^[\w-]{6,32}$/.test(id)) continue;
      const old=seen.get(anchor); if(old?.id===id)continue; if(old)old.host.remove();
      const host=document.createElement('span'); host.style.cssText='position:absolute;right:8px;top:8px;z-index:1000;display:block';
      const root=host.attachShadow({mode:'closed'});
      root.innerHTML=`<style>
:host{font:13px/1.35 system-ui,sans-serif;color:#f4f6ff;letter-spacing:.01em}
.control{border:1px solid #ffffff66;border-radius:10px;background:rgba(18,25,43,.92);color:#fff;cursor:pointer;padding:4px 6px;display:flex;gap:4px;align-items:center;box-shadow:0 4px 16px #0008;transition:background .16s,transform .16s}
.control:hover{background:#4b4277;transform:translateY(-1px)}.control img{width:20px;height:20px}
.menu{position:absolute;right:0;top:38px;width:min(375px,calc(100vw - 24px));max-height:min(480px,70vh);overflow:auto;border:1px solid #ffffff55;border-radius:16px;background:rgba(19,24,42,.97);box-shadow:0 12px 32px #000b;backdrop-filter:blur(20px);padding:10px;scrollbar-width:thin;scrollbar-color:#987fe3 transparent}
.menu[hidden]{display:none}.menu>div>div:first-child{padding:4px}.menu label{display:flex;align-items:center;justify-content:space-between;gap:8px;color:#c1c9e3}.menu input,.menu select{box-sizing:border-box;max-width:100%;color:#fff;background:#252d46;border:1px solid #7787ab;border-radius:8px;padding:7px}.menu input{width:100%;margin-top:7px}
.menu button{width:100%;border:1px solid transparent;border-radius:8px;color:inherit;text-align:left;background:transparent;padding:7px 9px;cursor:pointer}.menu button:hover{background:#7d65b845;border-color:#b9a5ef77}.menu button:focus-visible,.menu select:focus-visible{outline:2px solid #ba9cff}
.menu section{margin:9px 0;padding:9px;border:1px solid #ffffff1f;border-radius:11px;background:#ffffff09}.menu section strong{display:block;color:#d9ccff;font-size:12px;letter-spacing:.04em;margin-bottom:5px}.menu section small{display:block;color:#aebbd1;margin:5px 0}.lookup-status{color:#f4f6ff;padding:6px 3px;font-weight:600;overflow-wrap:anywhere}.menu .quality{background:#ffffff0b;margin:2px 0}.menu .subtitle-list{max-height:150px;overflow:auto;padding:0}.menu .subtitle-list button{padding:5px 7px}.menu .subtitle-list button[aria-pressed=true]{background:#8467d96b;border-color:#c9b8ff}
</style><button type="button" class="control" aria-label="Auralis video qualities" aria-expanded="false"><img alt=""><span>⌄</span></button><div class="menu" hidden></div>`;
      root.querySelector('img').src='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAIg0lEQVR4nHWXW4xW1RXHf2ufc77bXJiB4TqMiNwZp8ELRcSiKBDB1JpqTDVp0NZqH0xf+tA0aTISm/Shj77YegvGVlMvbZpqsUGoRWMU0FFgpCBDuY3AXL65MZdzzt6rD+ec7/sG9Mus2fvsfc5ea//Xf629l5D9VAURBfCKJW7vutw6+MHRGYQhhDkImS4kbS6EHKmE0EDNWBiSI8dNc9qHn3im7vxUPJ6oQkVIdEmtclWVpb969rHRjz/cMdV3YbVGUT0qyUuaGSppC0IyJwqopn1Nl07GBcU3wVhzcV739bM37Hp1/8+fFxHNjPDp7DSI6MOqzQse+MVfRj7+aHM8XAYUkURZ0kjyLJndCupQQMSgkoypMr0FVLX50vCpDeeGjm3YeH33g0O/0wfl1zLUSafxAfapeg8/8OSb5b17N2kcRiaX9zJViGSd9E9AFa/UxMz2+wj8AgOH/8rk2MXU4Ex5gkpmBIqOT5btga/3bP7By0++qapbn5KnnM/One5nOuvR0QMHNxFHoZcv5FBFjMGIQUQQk7YiiBhQS3PH3Vyz7ZeUgFIQcOaT5wBB1aGqqTjUVVoJ/IIJ7VR4ZPDgpp+sf2bHS+x8wVdVmbP1x4/H5bIz+YKHKp7n4/mZeJVn4/t4Rsg1zmLh7Q9RV6cUImXZLT8kLh9grHwGtYq1MTa22DhOxMbYKMZZS84reCNh2R3u++RxVX3RvwsWRH19KwWMICoiqIKNLDZ2qRck9bugLqZ57i1cLizm8kWlECsNXgum8B0Gew+CeCljExQyV2RcAQwgg1N9K7t2sMAf3dvVRGyLIiZ7oQJ1BjsZ9ChesZlZa+/HCwQ8wZOE7W2r72Og5z3Gx3oBg6pLFKeS8KFKWqu2eKDc1WQkCFQwFSUmNWS6eKnvlfql6ylecz1qlanhc0xeOoEC9TPbmLd4UxKaNd9UpWZ9kjFPAjVX7pgrlFeeEfxSE00334v4BjHC0OG/cenTVzLK07b8+5Tq5qcoXr0JKutlGSTxRxLjmKuUV8Qku69bupbSkhvAKWG5j2LLMhoW38ZE/xkUoWnWdcxftDFZTbwrUJDKRrKNVQz4RqUVyDwEwSs20HTzPZichzohvHichhVbmNW+hYnh07jYIgauXbqdYqnlW1CokasQSGERpAJVRZxSWrKG0oq14JR4pI+JM58mxHKOsUtfMj54Cocyq2UFra23ppm0BvKalpTYNQikYZZ9kLoks9QrlJjx3e2YYgAijJ/4ADs2gPgJxDYap+/UPkQEY4QlS+6hUGhOFFTgliwCk7WvRsBUEKhmPQF1FBe3U9e+Diy48SnGjr6HeH5yHACeX6D/9H4mRgZxwJzZq2mdvzZJwjV+rw3rb0Egm6habYI8jeu24dUVABg7+m/ioQsYL8jyDWIM8dQYvSffTXKFb1i+eDuFXGMyX0EgWbviasDPEKCGA5UXrKOwZCX1azagkaIxFNramfej3yMuB4BzMHvlvSxYvIWCGmysxAqtc9fQOucGTp79TzXENT1FqSJQMUC4EgVBgoDG9Vvxm0rYsgMx5OYuhAg0AkaS9Uot8yjFyUVEQlDrCAKPVddu4+yFQ0TxxDSl1dRew4ErRZ0l37aUhrUb0VArcavWEQ0OMP7V58mXBobPdjPWfx51LmG/MUSxsmjezbS2dODUJXnmKj0ZB77BCDE+MzZswZ/ZCCJM9nxBPDyABAYJCsTDF1EbgcLUcC/GL2I8QxxNcKH3ICJCPgjoWLSNnFdA0SrKFQZMQ6Dmv7XkFy6iYf0dECtqLUPvv8HA7udwUyFeqY6Gjq2I56MKLcs3k6+fCU45dvgVjhx5hTCawDplybx1LGhejXPu2xGoJWIyami8bTO5OTNBhIn/Hmbi5FEuH9nPwDt/ROMoPekgOXaTY/v4Z3/i9PF/MFg+ydlzHyFGKOULrFl0N4GXS+kn1P6mIUDK/NyCNmZsvAu1isbK8Ee7seOjoDDy2bsM7HkBVZfQQhXjGU5/9hqnj7yOcxZrQ46f+hdT4RTWKavmb6C1aQXO2aqebyRhen9ovO0Ocq1zkt1/9SWXjx4CMUnYO8dI19sMvv8ioJjA0Pvp65z7/DWsjVEFg+Fifzdnvj6AGKG+UMcNbVvxxK9crjMDfI0iyQbUOvILF9J05xawDrXC8P5/YkeHED9AXXJTVucY+eJt7OggvpdjtOdDbBwmLtSEbjaaoLtnNyvnriOPR8f873Ho1DucLndX3GA1EtNw55ohCYIJwaDOUli2nMKShUjeMHmqh7Guj5NY0yTvatbGEaPH91Hu3o0NkzjXjBeqiHic6/uCMxe7yPmG2fVNXDezI72mGXwJJtYuWDNk3oNef3bLMcQ4Mb6b7Olh7NBhogt9DL79OvFwGdJ7Ypb8tXLH8xATZHf/dLp6LQ+jcQ6eeIuLw1/TM9DD/8rdiHgOjGvOtxxb8yy9ArDqqZd+2v/nvz8fDfaHJp/LBc0z8fIlooFLEMfpgUI1kyFcQeaK8qSf1QIOEUNjcTbOxoxM9hPGU2FjviV3T9u9j/3hw0dfMHR2mgc7H9lVvLF9n5cr5jSMo3hgwE2dP6saRVmhVWlBNANhmqRzCQDVd51zOjjWq0Pjl1wUR5HvlXIrm9r3PfvbR3Z10mkMwE4R2/Hq0/c3bNywJ2iaFagVo07FxVY0isSFoWgUiosicVEoGoeicSRqE3E2EheHYuNQrI3E2lBsHElsI4ldLM6pOMTUF1qCG+fduueN7U/fL5vEVmOhpjht/82rj40ePLQj6utfrWFUX8mOlYKzWpwmBWoqaT/bf1aoohCYYGxGoaV7VctNu17e+9C04rTqyZry3BQL3NE10Tr2wYkZYVqCh1eU5ZnkgPqwWp7nqfZzQD3Q0bRs+Ilniuen4snU9mp5/n8XlEMBLpOuTQAAAABJRU5ErkJggg==';
      const button=root.querySelector('.control'),menu=root.querySelector('.menu');
      host.addEventListener('click',e=>e.stopPropagation());
      button.addEventListener('click',e=>{
        e.preventDefault();e.stopPropagation();menu.hidden=!menu.hidden;button.setAttribute('aria-expanded',String(!menu.hidden));
        if(menu.hidden)return;
        menu.replaceChildren();
        const controls=document.createElement('div');
        controls.innerHTML='<label>Cookies <select aria-label="Cookies"><option value="browser">Browser session</option><option value="file">Choose cookies file</option></select></label><input type="file" accept=".txt,text/plain" aria-label="Cookies file" hidden><button type="button" class="fetch">Fetch qualities</button><button type="button" class="sign-in">Sign in to YouTube</button>';
        const mode=controls.querySelector('select'),input=controls.querySelector('input');
        mode.addEventListener('change',()=>{input.hidden=mode.value!=='file';});
        const result=document.createElement('div');
        controls.querySelector('.sign-in').addEventListener('click',async e=>{e.preventDefault();e.stopPropagation();const r=await ext.runtime.sendMessage({type:'youtube-sign-in'}).catch(()=>null);result.textContent=r?.ok?(r.signedIn?'YouTube sign-in cookies found. Fetch qualities using Browser session.':'Sign in on the Google page, then return and fetch qualities.'):(r?.error||'Could not check YouTube sign-in.')});
        controls.querySelector('.fetch').addEventListener('click',async e=>{e.preventDefault();e.stopPropagation();const file=input.files?.[0];if(mode.value==='file'&&(!file||file.size>262144)){result.textContent='Choose a cookies.txt file under 256 KB.';return}const content=mode.value==='file'?await file.text():undefined;void lookup(`https://www.youtube.com/watch?v=${id}`,result,mode.value,content)});
        menu.append(controls,result); void lookup(`https://www.youtube.com/watch?v=${id}`,result,'browser','');
      });
      if (getComputedStyle(anchor).position === 'static') anchor.style.position='relative';
      anchor.append(host); seen.set(anchor,{id,host});
    }
  }
  new MutationObserver(() => { if (!scan.pending) { scan.pending=true; requestAnimationFrame(()=>{scan.pending=false;scan()}); } }).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['href']});
  scan();
})();
