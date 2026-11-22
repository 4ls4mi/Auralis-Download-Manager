// Auralis controls on YouTube cards work even before hover previews create a <video>.
(() => {
  // Content scripts can be reinjected into a live YouTube page after an extension update.
  // Tear down the previous instance, including any detached floating panel.
  globalThis.__auralisThumbnail?.teardown?.();
  for (const old of document.querySelectorAll('[data-auralis-thumbnail-control], [data-auralis-thumbnail-menu]')) old.remove();
  const ext = globalThis.browser ?? globalThis.chrome;
  const seen = new WeakMap();
  const entries = new Set();
  let disposed = false, scanFrame = 0;
  let activeMenu = null;
  const panelResize = new ResizeObserver(() => activeMenu?.position());
  document.addEventListener('pointerdown', e => {
    if (activeMenu && !e.composedPath().includes(activeMenu.host) && !e.composedPath().includes(activeMenu.portal)) activeMenu.close();
  }, true);
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && activeMenu) activeMenu.close(true); });
  addEventListener('resize', () => activeMenu?.position());
  addEventListener('scroll', () => activeMenu?.position(), true);
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  const sizeLabel = item => {
    const bytes=Number(item?.size);
    if (!Number.isFinite(bytes) || bytes<=0) return 'Size unavailable';
    const units=[['GB',1024**3],['MB',1024**2],['KB',1024],['B',1]];
    const [unit,scale]=units.find(([,value])=>bytes>=value);
    return `${item.approx?'~':''}${(bytes/scale).toLocaleString(undefined,{maximumFractionDigits:1})} ${unit}`;
  };
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
      for(const [kind,tracks] of [['manual',answer.subtitles||[]],['auto',answer.automatic_subtitles||[]]]) {
        const addChoice=(value,label)=>{const option=document.createElement('button');option.type='button';option.textContent=label;option.setAttribute('aria-pressed','false');option.addEventListener('click',event=>{event.preventDefault();event.stopPropagation();subs.value=value;list.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b===option)))});list.append(option)};
        if(tracks.length)addChoice(`${kind}:all`,kind==='auto'?'All automatic captions':'All subtitles');
        for(const track of tracks)addChoice(`${kind}:${track.code}`,`${track.name||track.code} (${track.code})${kind==='auto'?' · automatic':''} · ${sizeLabel(track)}`);
      }
      if(list.childElementCount)subsSection.append(list);
      const videoSection=document.createElement('section'), audioSection=document.createElement('section');
      const videoTitle=document.createElement('strong'),audioTitle=document.createElement('strong');videoTitle.textContent='Video qualities';audioTitle.textContent='Audio qualities';videoSection.append(videoTitle);audioSection.append(audioTitle);
      let videoCount=0,audioCount=0;
      for (const [index,choice] of answer.choices.entries()) {
        const button=document.createElement('button'); button.type='button';
        button.className='quality'; button.textContent = `${choice.label || choice.ext || 'Download'} · ${sizeLabel(choice)}  ↓`;
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
      const tabs=document.createElement('div');tabs.className='quality-tabs';tabs.setAttribute('role','tablist');tabs.setAttribute('aria-label','Quality categories');
      const sections=[['Video',videoSection],['Audio',audioSection],['Subtitles',subsSection]];
      const selectTab=index=>{sections.forEach(([,section],i)=>{section.hidden=i!==index;tabs.children[i].setAttribute('aria-selected',String(i===index));tabs.children[i].tabIndex=i===index?0:-1})};
      sections.forEach(([name],index)=>{const tab=document.createElement('button');tab.type='button';tab.textContent=name;tab.setAttribute('role','tab');tab.addEventListener('click',event=>{event.preventDefault();event.stopPropagation();selectTab(index)});tab.addEventListener('keydown',event=>{if(event.key!=='ArrowLeft'&&event.key!=='ArrowRight')return;event.preventDefault();const next=(index+(event.key==='ArrowRight'?1:2))%3;selectTab(next);tabs.children[next].focus()});tabs.append(tab)});
      menu.append(tabs,videoSection,audioSection,subsSection);selectTab(videoCount?0:audioCount?1:2);
    } catch { status.textContent='Could not reach Auralis.'; }
  }
  function scan() {
    for (const entry of entries) if (!entry.host.isConnected) { entry.close(); entries.delete(entry); }
    for (const anchor of document.querySelectorAll('a#thumbnail[href*="watch?v="]')) {
      const href = new URL(anchor.href, location.href); const id=href.searchParams.get('v');
      if (!id || !/^[\w-]{6,32}$/.test(id)) continue;
      const old=seen.get(anchor); if(old?.id===id && old.host.isConnected)continue; if(old){old.close();old.host.remove();entries.delete(old);}
      const host=document.createElement('span'); host.style.cssText='position:absolute;right:8px;top:8px;z-index:1000;display:block';
      host.setAttribute('data-auralis-thumbnail-control','');
      const root=host.attachShadow({mode:'closed'});
      root.innerHTML=`<style>
:host{font:13px/1.35 system-ui,sans-serif;color:#f4f6ff;letter-spacing:.01em}
.control{border:1px solid #ffffff66;border-radius:10px;background:rgba(18,25,43,.92);color:#fff;cursor:pointer;padding:4px 6px;display:flex;gap:4px;align-items:center;box-shadow:0 4px 16px #0008;transition:background .16s,transform .16s}
.control:hover{background:#4b4277;transform:translateY(-1px)}.control img{width:20px;height:20px}
.menu{position:absolute;right:0;top:38px;width:min(375px,calc(100vw - 24px));max-height:min(480px,70vh);overflow:auto;border:1px solid #ffffff55;border-radius:16px;background:rgba(19,24,42,.97);box-shadow:0 12px 32px #000b;backdrop-filter:blur(20px);padding:10px;scrollbar-width:thin;scrollbar-color:#987fe3 transparent}
.menu[hidden]{display:none}.menu>div>div:first-child{padding:4px}.menu label{display:flex;align-items:center;justify-content:space-between;gap:8px;color:#c1c9e3}.menu input,.menu select{box-sizing:border-box;max-width:100%;color:#fff;background:#252d46;border:1px solid #7787ab;border-radius:8px;padding:7px}.menu input{width:100%;margin-top:7px}
.menu button{width:100%;border:1px solid transparent;border-radius:8px;color:inherit;text-align:left;background:transparent;padding:7px 9px;cursor:pointer}.menu button:hover{background:#7d65b845;border-color:#b9a5ef77}.menu button:focus-visible,.menu select:focus-visible{outline:2px solid #ba9cff}
.menu section{margin:9px 0;padding:9px;border:1px solid #ffffff1f;border-radius:11px;background:#ffffff09}.menu section strong{display:block;color:#d9ccff;font-size:12px;letter-spacing:.04em;margin-bottom:5px}.menu section small{display:block;color:#aebbd1;margin:5px 0}.lookup-status{color:#f4f6ff;padding:6px 3px;font-weight:600;overflow-wrap:anywhere}.menu .quality{background:#ffffff0b;margin:2px 0}.menu .subtitle-list{max-height:150px;overflow:auto;padding:0}.menu .subtitle-list button{padding:5px 7px}.menu .subtitle-list button[aria-pressed=true]{background:#8467d96b;border-color:#c9b8ff}
.menu .cookie-row{display:flex;align-items:flex-start;justify-content:space-between;gap:8px;color:#c1c9e3}.menu .cookie-combo{position:relative;flex:1;min-width:0}.menu .cookie-trigger{display:flex;justify-content:space-between;align-items:center;background:linear-gradient(145deg,#435978cc,#1b2b43e8);border:1px solid #a8bde088;padding:5px 7px;font-size:12px}.menu .cookie-list{margin-top:3px;padding:3px;border:1px solid #a8bde066;border-radius:8px;background:#182840f5}.menu .cookie-list[hidden]{display:none}.menu .cookie-list button{padding:4px 7px;font-size:12px}.menu .cookie-list button[aria-selected=true]{background:#856dba80;box-shadow:inset 2px 0 #d9c3ff}
.menu .quality-tabs{display:flex;gap:4px;margin:5px 0}.menu .quality-tabs button{width:auto;flex:1;text-align:center;padding:5px 3px;font-size:12px}.menu .quality-tabs button[aria-selected="true"]{background:#8467d96b;border-color:#c9b8ff}.menu section[hidden]{display:none}.menu section{margin:4px 0;padding:5px}.menu .subtitle-list{max-height:none}
</style><button type="button" class="control" aria-label="Auralis video qualities" aria-expanded="false"><img alt=""><span>⌄</span></button><div class="menu" hidden></div>`;
      root.querySelector('img').src='data:image/png;base64,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';
      const button=root.querySelector('.control'),menu=root.querySelector('.menu');
      // The thumbnail and its ancestors often clip overflow. Keep the small button on the
      // thumbnail, but render its panel in a separate viewport-level shadow root.
      const portal=document.createElement('div');
      portal.setAttribute('data-auralis-thumbnail-menu','');
      portal.style.cssText='position:fixed;inset:0;pointer-events:none;z-index:2147483647';
      const panelRoot=portal.attachShadow({mode:'closed'});
      panelRoot.append(root.querySelector('style').cloneNode(true));
      const portalStyle=document.createElement('style');
      portalStyle.textContent='.menu{position:fixed;top:0;left:0;right:auto;width:min(310px,calc(100vw - 16px));height:min(320px,calc(100vh - 16px));min-width:min(260px,calc(100vw - 16px));min-height:180px;max-width:calc(100vw - 16px);max-height:calc(100vh - 16px);resize:both;overflow:auto;box-sizing:border-box;pointer-events:auto;background:linear-gradient(145deg,rgba(55,80,114,.87),rgba(18,28,49,.94));border:1px solid #c8e8ff80;box-shadow:inset 0 1px #fff8,0 18px 42px #000b;backdrop-filter:blur(22px) saturate(135%)}.dragbar{display:flex;align-items:center;justify-content:space-between;padding:8px 10px;margin:-3px -3px 8px;border-radius:10px;background:linear-gradient(110deg,#a9e4ff35,#bd9cff20);color:#fff;font-weight:700;cursor:default;user-select:none}.dragbar small{font-weight:400;color:#d6e9ff}';
      panelRoot.append(portalStyle,menu);
      const positionMenu=()=>{
        if(menu.hidden)return;
        const r=button.getBoundingClientRect(),pad=8,w=menu.getBoundingClientRect().width,h=menu.getBoundingClientRect().height;
        const top=r.bottom+6+h<=innerHeight-pad?r.bottom+6:Math.max(pad,r.top-h-6);
        menu.style.top=Math.max(pad,Math.min(top,innerHeight-pad-h))+'px';
        menu.style.left=Math.max(pad,Math.min(r.right-w,innerWidth-pad-w))+'px';
      };
      const closeMenu=(focus=false)=>{menu.hidden=true;button.setAttribute('aria-expanded','false');if(activeMenu?.portal===portal){panelResize.disconnect();activeMenu=null}portal.remove();if(focus)button.focus()};
      const entry={host,portal,position:positionMenu,close:closeMenu};
      host.addEventListener('click',e=>e.stopPropagation());
      button.addEventListener('click',e=>{
        e.preventDefault();e.stopPropagation();
        if(!menu.hidden){closeMenu();return}
        activeMenu?.close();document.body.append(portal);menu.hidden=false;button.setAttribute('aria-expanded','true');activeMenu=entry;panelResize.observe(menu);
        positionMenu();
        menu.replaceChildren();
        const dragbar=document.createElement('div');dragbar.className='dragbar';dragbar.innerHTML='<span>Auralis · Video qualities</span>';menu.append(dragbar);
        const controls=document.createElement('div');
        controls.innerHTML='<div class="cookie-row"><span>Cookies</span><span class="cookie-combo"><select hidden tabindex="-1" aria-hidden="true"><option value="browser">Browser session</option><option value="file">Choose cookies file</option></select><button type="button" class="cookie-trigger" role="combobox" aria-label="Cookies" aria-haspopup="listbox" aria-expanded="false"><span>Browser session</span><span aria-hidden="true">▾</span></button><span class="cookie-list" role="listbox" aria-label="Cookie sources" hidden><button type="button" role="option" data-value="browser" aria-selected="true">Browser session</button><button type="button" role="option" data-value="file" aria-selected="false">Choose cookies file</button></span></span></div><input type="file" accept=".txt,text/plain" aria-label="Cookies file" hidden><button type="button" class="fetch">Fetch qualities</button>';
        const mode=controls.querySelector('select'),input=controls.querySelector('input'),trigger=controls.querySelector('.cookie-trigger'),list=controls.querySelector('.cookie-list'),options=[...list.querySelectorAll('[role="option"]')];
        const close=()=>{list.hidden=true;trigger.setAttribute('aria-expanded','false')};
        trigger.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();list.hidden=!list.hidden;trigger.setAttribute('aria-expanded',String(!list.hidden))});
        for(const option of options)option.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();mode.value=option.dataset.value;input.hidden=mode.value!=='file';trigger.firstElementChild.textContent=option.textContent;for(const other of options)other.setAttribute('aria-selected',String(other===option));close();trigger.focus()});
        controls.querySelector('.cookie-combo').addEventListener('keydown',e=>{if(e.key==='Escape'&&!list.hidden){e.preventDefault();e.stopPropagation();close();trigger.focus()}else if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();e.stopPropagation();list.hidden=false;trigger.setAttribute('aria-expanded','true');const index=options.indexOf(panelRoot.activeElement);options[(index+(e.key==='ArrowDown'?1:options.length-1))%options.length].focus()}});
        const result=document.createElement('div');
        controls.querySelector('.fetch').addEventListener('click',async e=>{e.preventDefault();e.stopPropagation();const file=input.files?.[0];if(mode.value==='file'&&(!file||file.size>262144)){result.textContent='Choose a cookies.txt file under 256 KB.';return}const content=mode.value==='file'?await file.text():undefined;void lookup(`https://www.youtube.com/watch?v=${id}`,result,mode.value,content)});
        menu.append(controls,result); void lookup(`https://www.youtube.com/watch?v=${id}`,result,'browser','');
      });
      if (getComputedStyle(anchor).position === 'static') anchor.style.position='relative';
      anchor.append(host); const record={id,host,portal,close:closeMenu}; seen.set(anchor,record); entries.add(record);
    }
  }
  const observer = new MutationObserver(() => { if (!scan.pending) { scan.pending=true; scanFrame=requestAnimationFrame(()=>{scan.pending=false;scanFrame=0;if(!disposed)scan()}); } });
  observer.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['href']});
  globalThis.__auralisThumbnail = {teardown(){disposed=true;observer.disconnect();if(scanFrame)cancelAnimationFrame(scanFrame);activeMenu?.close();for(const entry of entries){entry.close();entry.host.remove()}entries.clear()}};
  scan();
})();
