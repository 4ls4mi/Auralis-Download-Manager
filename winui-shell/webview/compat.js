/* Development adapter for the local WinUI WebView. Not included in a release.
   Only explicit, validated operations are forwarded to the native host. */
(() => {
  const webview = globalThis.chrome?.webview;
  if (!webview) throw new Error('The WinUI WebView host is unavailable.');
  let nextId = 1;
  const pending = new Map();
  webview.addEventListener('message', event => {
    const message = event.data;
    if (!message || !Number.isSafeInteger(message.id)) return;
    const request = pending.get(message.id);
    if (!request) return;
    pending.delete(message.id);
    clearTimeout(request.timer);
    if (message.ok === true) request.resolve(message.value);
    else request.reject(new Error(typeof message.error === 'string' ? message.error : 'Native request failed.'));
  });
  function invoke(command, args = {}) {
    let payload;
    if (command === 'dashboard_snapshot' || command === 'dashboard_visuals') payload = {command};
    else if (command === 'download_action' && ['start', 'pause'].includes(args.action) &&
             Array.isArray(args.ids) && args.ids.length === 1 && Number.isSafeInteger(args.ids[0]) && args.ids[0] > 0)
      payload = {command: args.action === 'start' ? 'start_download' : 'pause_download', downloadId: args.ids[0]};
    else if (command === 'add_download' && typeof args.url === 'string' && typeof args.later === 'boolean')
      payload = {command, url: args.url, later: args.later};
    else return Promise.reject(new Error(`WinUI command is not implemented: ${command}`));
    if (nextId > Number.MAX_SAFE_INTEGER) return Promise.reject(new Error('WinUI request limit reached.'));
    const id = nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { pending.delete(id); reject(new Error('Native request timed out.')); }, 30000);
      pending.set(id, {resolve, reject, timer});
      try { webview.postMessage({id, ...payload}); }
      catch (error) { clearTimeout(timer); pending.delete(id); reject(error); }
    });
  }
  globalThis.__TAURI_INTERNALS__ = {
    invoke,
    metadata: {currentWindow:{label:'main'}, currentWebview:{label:'main'}},
    convertFileSrc() { throw new Error('Local file access is not implemented in the WinUI shell.'); }
  };
})();
