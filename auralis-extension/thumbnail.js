// Auralis controls on YouTube cards work even before hover previews create a <video>.
(() => {
  const ext = globalThis.browser ?? globalThis.chrome;
  const seen = new WeakMap();
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  async function lookup(url, menu, cookieMode, cookieHeader) {
    menu.replaceChildren();
    const status = document.createElement('div'); status.textContent = 'Looking up qualities…'; menu.append(status);
    try {
      let r = await ext.runtime.sendMessage({type:'video-lookup',url,thumbnail:true,cookieMode,cookieHeader});
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
      for (const [index,choice] of answer.choices.entries()) {
        const button=document.createElement('button'); button.type='button';
        button.textContent = `${choice.audio ? 'Audio' : 'Video'} · ${choice.label || choice.ext || 'Download'}`;
        button.addEventListener('click', async event => {
          event.preventDefault(); event.stopPropagation(); button.disabled=true;
          try { const result=await ext.runtime.sendMessage({type:'video-pick',token:answer.token,choice:index});
            status.textContent=['started','queued','sent'].includes(result?.lookup?.state)?'Added to Auralis':'Could not start this download.';
          } catch { status.textContent='Could not reach Auralis.'; }
          button.disabled=false;
        });
        menu.append(button);
      }
    } catch { status.textContent='Could not reach Auralis.'; }
  }
  function scan() {
    for (const anchor of document.querySelectorAll('a#thumbnail[href*="watch?v="]')) {
      const href = new URL(anchor.href, location.href); const id=href.searchParams.get('v');
      if (!id || !/^[\w-]{6,32}$/.test(id)) continue;
      const old=seen.get(anchor); if(old?.id===id)continue; if(old)old.host.remove();
      const host=document.createElement('span'); host.style.cssText='position:absolute;right:8px;top:8px;z-index:1000;display:block';
      const root=host.attachShadow({mode:'closed'});
      root.innerHTML=`<style>:host{font:13px system-ui;color:#eff8ff}.control{border:1px solid #b3d8ff88;border-radius:9px;background:#101d34eF;color:white;cursor:pointer;padding:4px;display:flex;gap:3px;align-items:center;box-shadow:0 3px 12px #0008}.control img{width:22px;height:22px}.menu{position:absolute;right:0;top:38px;width:250px;max-height:320px;overflow:auto;border:1px solid #b3d8ff88;border-radius:10px;background:#101d34f5;box-shadow:0 8px 24px #000a;padding:8px}.menu[hidden]{display:none}.menu div{padding:7px}.menu button{display:block;width:100%;border:0;border-radius:6px;color:inherit;text-align:left;background:transparent;padding:8px;cursor:pointer}.menu button:hover{background:#526fb888}</style><button type="button" class="control" aria-label="Auralis video qualities" aria-expanded="false"><img alt=""><span>⌄</span></button><div class="menu" hidden></div>`;
      root.querySelector('img').src='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAIg0lEQVR4nHWXW4xW1RXHf2ufc77bXJiB4TqMiNwZp8ELRcSiKBDB1JpqTDVp0NZqH0xf+tA0aTISm/Shj77YegvGVlMvbZpqsUGoRWMU0FFgpCBDuY3AXL65MZdzzt6rD+ec7/sG9Mus2fvsfc5ea//Xf629l5D9VAURBfCKJW7vutw6+MHRGYQhhDkImS4kbS6EHKmE0EDNWBiSI8dNc9qHn3im7vxUPJ6oQkVIdEmtclWVpb969rHRjz/cMdV3YbVGUT0qyUuaGSppC0IyJwqopn1Nl07GBcU3wVhzcV739bM37Hp1/8+fFxHNjPDp7DSI6MOqzQse+MVfRj7+aHM8XAYUkURZ0kjyLJndCupQQMSgkoypMr0FVLX50vCpDeeGjm3YeH33g0O/0wfl1zLUSafxAfapeg8/8OSb5b17N2kcRiaX9zJViGSd9E9AFa/UxMz2+wj8AgOH/8rk2MXU4Ex5gkpmBIqOT5btga/3bP7By0++qapbn5KnnM/One5nOuvR0QMHNxFHoZcv5FBFjMGIQUQQk7YiiBhQS3PH3Vyz7ZeUgFIQcOaT5wBB1aGqqTjUVVoJ/IIJ7VR4ZPDgpp+sf2bHS+x8wVdVmbP1x4/H5bIz+YKHKp7n4/mZeJVn4/t4Rsg1zmLh7Q9RV6cUImXZLT8kLh9grHwGtYq1MTa22DhOxMbYKMZZS84reCNh2R3u++RxVX3RvwsWRH19KwWMICoiqIKNLDZ2qRck9bugLqZ57i1cLizm8kWlECsNXgum8B0Gew+CeCljExQyV2RcAQwgg1N9K7t2sMAf3dvVRGyLIiZ7oQJ1BjsZ9ChesZlZa+/HCwQ8wZOE7W2r72Og5z3Gx3oBg6pLFKeS8KFKWqu2eKDc1WQkCFQwFSUmNWS6eKnvlfql6ylecz1qlanhc0xeOoEC9TPbmLd4UxKaNd9UpWZ9kjFPAjVX7pgrlFeeEfxSE00334v4BjHC0OG/cenTVzLK07b8+5Tq5qcoXr0JKutlGSTxRxLjmKuUV8Qku69bupbSkhvAKWG5j2LLMhoW38ZE/xkUoWnWdcxftDFZTbwrUJDKRrKNVQz4RqUVyDwEwSs20HTzPZichzohvHichhVbmNW+hYnh07jYIgauXbqdYqnlW1CokasQSGERpAJVRZxSWrKG0oq14JR4pI+JM58mxHKOsUtfMj54Cocyq2UFra23ppm0BvKalpTYNQikYZZ9kLoks9QrlJjx3e2YYgAijJ/4ADs2gPgJxDYap+/UPkQEY4QlS+6hUGhOFFTgliwCk7WvRsBUEKhmPQF1FBe3U9e+Diy48SnGjr6HeH5yHACeX6D/9H4mRgZxwJzZq2mdvzZJwjV+rw3rb0Egm6habYI8jeu24dUVABg7+m/ioQsYL8jyDWIM8dQYvSffTXKFb1i+eDuFXGMyX0EgWbviasDPEKCGA5UXrKOwZCX1azagkaIxFNramfej3yMuB4BzMHvlvSxYvIWCGmysxAqtc9fQOucGTp79TzXENT1FqSJQMUC4EgVBgoDG9Vvxm0rYsgMx5OYuhAg0AkaS9Uot8yjFyUVEQlDrCAKPVddu4+yFQ0TxxDSl1dRew4ErRZ0l37aUhrUb0VArcavWEQ0OMP7V58mXBobPdjPWfx51LmG/MUSxsmjezbS2dODUJXnmKj0ZB77BCDE+MzZswZ/ZCCJM9nxBPDyABAYJCsTDF1EbgcLUcC/GL2I8QxxNcKH3ICJCPgjoWLSNnFdA0SrKFQZMQ6Dmv7XkFy6iYf0dECtqLUPvv8HA7udwUyFeqY6Gjq2I56MKLcs3k6+fCU45dvgVjhx5hTCawDplybx1LGhejXPu2xGoJWIyami8bTO5OTNBhIn/Hmbi5FEuH9nPwDt/ROMoPekgOXaTY/v4Z3/i9PF/MFg+ydlzHyFGKOULrFl0N4GXS+kn1P6mIUDK/NyCNmZsvAu1isbK8Ee7seOjoDDy2bsM7HkBVZfQQhXjGU5/9hqnj7yOcxZrQ46f+hdT4RTWKavmb6C1aQXO2aqebyRhen9ovO0Ocq1zkt1/9SWXjx4CMUnYO8dI19sMvv8ioJjA0Pvp65z7/DWsjVEFg+Fifzdnvj6AGKG+UMcNbVvxxK9crjMDfI0iyQbUOvILF9J05xawDrXC8P5/YkeHED9AXXJTVucY+eJt7OggvpdjtOdDbBwmLtSEbjaaoLtnNyvnriOPR8f873Ho1DucLndX3GA1EtNw55ohCYIJwaDOUli2nMKShUjeMHmqh7Guj5NY0yTvatbGEaPH91Hu3o0NkzjXjBeqiHic6/uCMxe7yPmG2fVNXDezI72mGXwJJtYuWDNk3oNef3bLMcQ4Mb6b7Olh7NBhogt9DL79OvFwGdJ7Ypb8tXLH8xATZHf/dLp6LQ+jcQ6eeIuLw1/TM9DD/8rdiHgOjGvOtxxb8yy9ArDqqZd+2v/nvz8fDfaHJp/LBc0z8fIlooFLEMfpgUI1kyFcQeaK8qSf1QIOEUNjcTbOxoxM9hPGU2FjviV3T9u9j/3hw0dfMHR2mgc7H9lVvLF9n5cr5jSMo3hgwE2dP6saRVmhVWlBNANhmqRzCQDVd51zOjjWq0Pjl1wUR5HvlXIrm9r3PfvbR3Z10mkMwE4R2/Hq0/c3bNywJ2iaFagVo07FxVY0isSFoWgUiosicVEoGoeicSRqE3E2EheHYuNQrI3E2lBsHElsI4ldLM6pOMTUF1qCG+fduueN7U/fL5vEVmOhpjht/82rj40ePLQj6utfrWFUX8mOlYKzWpwmBWoqaT/bf1aoohCYYGxGoaV7VctNu17e+9C04rTqyZry3BQL3NE10Tr2wYkZYVqCh1eU5ZnkgPqwWp7nqfZzQD3Q0bRs+Ilniuen4snU9mp5/n8XlEMBLpOuTQAAAABJRU5ErkJggg==';
      const button=root.querySelector('.control'),menu=root.querySelector('.menu');
      host.addEventListener('click',e=>{e.preventDefault();e.stopPropagation()});
      button.addEventListener('click',e=>{
        e.preventDefault();e.stopPropagation();menu.hidden=!menu.hidden;button.setAttribute('aria-expanded',String(!menu.hidden));
        if(menu.hidden)return;
        menu.replaceChildren();
        const controls=document.createElement('div');
        controls.innerHTML='<label>Cookies <select aria-label="Cookies"><option value="browser">Browser session</option><option value="manual">Paste cookies</option></select></label><input type="password" placeholder="name=value; …" aria-label="Cookie header" hidden><button type="button">Fetch qualities</button><small>App-wide manual cookie file may take priority.</small>';
        const mode=controls.querySelector('select'),input=controls.querySelector('input');
        mode.addEventListener('change',()=>{input.hidden=mode.value!=='manual';});
        const result=document.createElement('div');
        controls.querySelector('button').addEventListener('click',()=>void lookup(`https://www.youtube.com/watch?v=${id}`,result,mode.value,input.value));
        menu.append(controls,result); void lookup(`https://www.youtube.com/watch?v=${id}`,result,'browser','');
      });
      if (getComputedStyle(anchor).position === 'static') anchor.style.position='relative';
      anchor.append(host); seen.set(anchor,{id,host});
    }
  }
  new MutationObserver(() => { if (!scan.pending) { scan.pending=true; requestAnimationFrame(()=>{scan.pending=false;scan()}); } }).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['href']});
  scan();
})();
