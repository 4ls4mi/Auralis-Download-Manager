// Exercise the shipped service worker with fake browser events and harmless fixture data.
// Run with node --test .github/scripts/test_auralis_extension_boundary.mjs.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const extension = new URL("../../auralis-extension/", import.meta.url);
const source = readFileSync(new URL("background.js", extension), "utf8");
const appearance = readFileSync(new URL("appearance-profile.js", extension), "utf8");
const plain = (value) => JSON.parse(JSON.stringify(value));

async function browser(firefox, { listCookies, links = [] } = {}) {
  const events = new Map();
  const native = [];
  const downloadActions = [];
  const saved = {};
  const event = (name) => ({ addListener(fn) {
    if (!events.has(name)) events.set(name, []);
    events.get(name).push(fn);
  } });
  const eventsFor = (prefix, names) => Object.fromEntries(names.map((name) => [name, event(prefix + name)]));
  const options = { ok: true, version: "0.5.2", types: "ZIP EXE", capture: true };
  const script = vm.createContext({
    URL, URLSearchParams, TextDecoder, console, setTimeout, clearTimeout,
    navigator: { userAgent: "Auralis fixture" },
    browser: {
      downloads: {
        ...(firefox ? { onCreated: event("download") } : { onDeterminingFilename: event("download") }),
        pause: async (id) => { downloadActions.push(["pause", id]); },
        resume: async (id) => { downloadActions.push(["resume", id]); },
        cancel: async (id) => { downloadActions.push(["cancel", id]); },
        erase: async ({ id }) => { downloadActions.push(["erase", id]); },
      },
      storage: { local: { get: async (keys) => Array.isArray(keys) ? saved : { ...keys, ...saved },
        set: async (values) => Object.assign(saved, values), remove: async (key) => delete saved[key] }, onChanged: event("storage") },
      runtime: {
        id: "fixture", getURL: (path) => `chrome-extension://fixture/${path}`,
        getManifest: () => ({ version: "0.1.17", permissions: [], optional_permissions: [], content_scripts: [] }),
        sendNativeMessage: async (host, message) => {
          native.push([host, plain(message)]);
          return message.hello || message.rules ? options : { ok: true };
        },
        ...eventsFor("runtime", ["onMessage", "onInstalled", "onStartup"]),
      },
      i18n: { getMessage: () => "" },
      tabs: {
        ...eventsFor("tab", ["onCreated", "onRemoved", "onUpdated"]),
        query: async () => [],
      },
      webRequest: eventsFor("request", ["onBeforeRequest", "onBeforeSendHeaders", "onSendHeaders",
        "onBeforeRedirect", "onResponseStarted", "onErrorOccurred", "onHeadersReceived"]),
      contextMenus: { onClicked: event("menu") },
      scripting: { executeScript: async () => [{ result: links }] },
      action: { setBadgeText: async () => {}, setBadgeBackgroundColor: async () => {}, setTitle: async () => {} },
      permissions: { contains: async () => true },
      cookies: { getAll: listCookies || (async () => [
        { name: "format", value: "standard", domain: "stream.example.test", path: "/videos", hostOnly: true, secure: true },
        { name: "preference", value: "other", domain: "stream.example.test", path: "/", hostOnly: true, secure: true },
      ]) },
    },
  });
  vm.runInContext(appearance, script);
  vm.runInContext(source, script);
  // Allow startup to cache rules before running the isolated scenarios.
  await new Promise((resolve) => setImmediate(resolve));
  return { script, native, downloadActions,
    emit(name, ...args) { return (events.get(name) ?? []).map((fn) => fn(...args)); },
    message(message, sender) {
      const [listener] = events.get("runtimeonMessage");
      return new Promise((resolve) => { if (listener(message, sender, resolve) === false) resolve(null); });
    },
  };
}

const form = {
  method: "POST", url: "https://files.example.test/export", requestId: "request-1", tabId: 4,
  originUrl: "https://files.example.test/reports", requestBody: { formData: { format: ["zip"] } },
};

test("browser-flagged downloads are handed over with a warning", async () => {
  const { script, native } = await browser(false);
  const url = "https://files.example.test/report.zip";
  const flagged = { url, danger: "content" };
  const candidate = await script.candidate(flagged, url);
  assert.equal(candidate.browserWarning, true);
  assert.equal(await script.offer(flagged, url, candidate), true);
  const handoff = native.find(([, message]) => message.url === url)?.[1];
  assert.equal(handoff.browserWarning, true);
  assert.equal(handoff.browserCredentialsUnavailable, true);
  assert.equal(handoff.cookies, "");
  assert.equal((await script.candidate({ url, danger: "safe" }, url)).browserWarning, false);
});

test("Firefox replays URL-encoded forms only for their browser request", async () => {
  const { script, emit } = await browser(true);
  const final = "https://files.example.test/report.zip";
  emit("requestonBeforeRequest", form);
  emit("requestonBeforeRedirect", { ...form, redirectUrl: final });
  const response = { tabId: 4, requestId: form.requestId, requestMethod: "GET", url: final };
  assert.equal(script.firstUrl(response), form.url);
  assert.equal(await script.pageOf(response, [form.url, final]), form.originUrl);
  assert.deepEqual(plain(script.postOf(response, [final], false)), {
    body: "format=zip", type: "application/x-www-form-urlencoded",
  });
  const otherResponse = { ...response, requestId: "request-2", tabId: 5 };
  assert.equal(script.firstUrl(otherResponse), final);
  assert.equal(await script.pageOf(otherResponse, [final]), "");
  assert.equal(script.postOf(otherResponse, [final], false), undefined);
});

test("Chromium leaves ambiguous form downloads to the browser", async () => {
  const { script, emit } = await browser(false);
  emit("requestonBeforeRequest", form);
  const final = "https://files.example.test/report.zip";
  emit("requestonBeforeRedirect", { ...form, redirectUrl: final });
  assert.equal(script.postOf({ url: final }, [final], false), null);
  const other = "https://files.example.test/guide.zip";
  assert.equal(script.postOf({ url: other }, [other], false), undefined);
});

test("video handoff retains observed cookies in their original scope", async () => {
  const { script, emit } = await browser(false);
  const url = "https://stream.example.test/videos/index.m3u8";
  const request = { tabId: 6, frameId: 1, requestId: "stream-1", url, type: "xmlhttprequest" };
  emit("requestonSendHeaders", { ...request, requestHeaders: [{ name: "Cookie", value: "format=standard; segment=1" }] });
  emit("requestonResponseStarted", { ...request, statusCode: 200,
    responseHeaders: [{ name: "Content-Type", value: "application/vnd.apple.mpegurl" }] });
  const withoutCookies = { ...request, frameId: 2, requestId: "stream-2" };
  emit("requestonSendHeaders", { ...withoutCookies, requestHeaders: [] });
  emit("requestonResponseStarted", { ...withoutCookies, statusCode: 200,
    responseHeaders: [{ name: "Content-Type", value: "application/vnd.apple.mpegurl" }] });
  await new Promise((resolve) => setImmediate(resolve));
  const sent = await script.streamContext(6, url, {}, 1);
  assert.equal(sent.cookies, "format=standard; segment=1");
  assert.deepEqual(plain(sent.cookieJar.map(({ name, path }) => [name, path])), [
    ["format", "/videos"], ["segment", "/videos/index.m3u8"],
  ]);
  const empty = await script.streamContext(6, url, {}, 2);
  assert.equal(empty.cookies, "");
  assert.equal(empty.cookieJar.length, 0);
});

test("extension UI, tab content, and unknown senders stay separately authorized", async () => {
  const { message, native } = await browser(false);
  const extensionId = { id: "fixture" };
  const popup = { ...extensionId, url: "chrome-extension://fixture/popup.html?page=remote" };
  assert.equal((await message({ type: "open-app" }, popup)).ok, true);
  const options = { ...extensionId, url: "chrome-extension://fixture/options.html" };
  assert.equal((await message({ type: "desktop-appearance" }, options)).ok, true);
  assert.equal(await message({ type: "open-app" }, options), null);
  assert.equal(await message({ type: "open-app" }, extensionId), null);
  const web = { ...extensionId, url: "https://www.example.test/", tab: { id: 8 } };
  assert.equal((await message({ type: "open-app" }, web)).ok, false);
  assert.equal((await message({ type: "companion-appearance" }, web)).ok, true);
  assert.equal(native.filter(([, entry]) => entry.open).length, 1);
});

test("automatic Firefox downloads keep the observed header or its explicit absence", async () => {
  let storeReads = 0;
  const { script, emit, native } = await browser(true, { listCookies: async () => { storeReads++; return []; } });
  const url = "https://files.example.test/report.zip";
  const response = { tabId: 4, type: "sub_frame", url, method: "GET", statusCode: 200,
    responseHeaders: [{ name: "Content-Type", value: "application/zip" }] };
  const standard = { ...response, requestId: "report-standard", frameId: 1 };
  const empty = { ...response, requestId: "report-empty", frameId: 2 };
  emit("requestonSendHeaders", { ...standard, requestHeaders: [{ name: "Cookie", value: "format=standard" }] });
  emit("requestonSendHeaders", { ...empty, requestHeaders: [] });
  assert.equal((await script.headersReceived(standard)).cancel, true);
  assert.equal((await script.headersReceived(empty)).cancel, true);
  assert.deepEqual(native.map(([, message]) => message).filter((message) => message.url === url)
    .map((message) => message.cookies), ["format=standard", ""]);
  assert.equal(storeReads, 0);
});

test("an observed anonymous Firefox redirect keeps its original download address", async () => {
  const { script, emit, native } = await browser(true);
  const first = { requestId: "report-redirect", tabId: 4, frameId: 1, type: "sub_frame", method: "GET",
    url: "https://files.example.test/export", requestHeaders: [] };
  const last = { ...first, url: "https://static.example.test/report.zip", statusCode: 200,
    responseHeaders: [{ name: "Content-Type", value: "application/zip" }] };
  emit("requestonSendHeaders", first);
  emit("requestonBeforeRedirect", { ...first, redirectUrl: last.url });
  emit("requestonSendHeaders", last);
  assert.equal((await script.headersReceived(last)).cancel, true);
  const [download] = native.map(([, message]) => message).filter((message) => message.url === first.url);
  assert.equal(download.finalUrl, last.url);
  assert.equal(download.cookies, "");
});

test("anonymous Chromium downloads can be handed over without a request ID", async () => {
  const publicUrl = "https://files.example.test/public.zip";
  const sessionUrl = "https://files.example.test/reports/export.zip";
  const unavailableUrl = "https://files.example.test/unavailable.zip";
  const { script, native } = await browser(false, { listCookies: async ({ url }) => {
    if (url === unavailableUrl) throw new Error("Cookie store unavailable");
    return url === sessionUrl ? [{ name: "format", value: "standard", path: "/reports" }] : [];
  } });
  const item = (url) => ({ url, page: "https://files.example.test/", danger: "safe" });
  assert.equal(await script.offer(item(publicUrl), publicUrl, { name: "public.zip" }), true);
  assert.equal(await script.offer(item(sessionUrl), sessionUrl, { name: "export.zip" }), true);
  assert.equal(await script.offer(item(unavailableUrl), unavailableUrl, { name: "unavailable.zip" }), true);
  const downloads = native.map(([, message]) => message).filter((message) => message.url);
  assert.deepEqual(downloads.map(({ url, cookies }) => [url, cookies]), [[publicUrl, ""], [sessionUrl, ""], [unavailableUrl, ""]]);
  assert.ok(downloads.slice(1).every((entry) => entry.browserCredentialsUnavailable));
  assert.equal(Boolean(downloads[0].browserCredentialsUnavailable), false);
});

const popup = { id: "fixture", url: "chrome-extension://fixture/popup.html" };

test("Chromium captures ReShade executables with uncertain cookies and browser danger flags", async () => {
  const url = "https://reshade.me/downloads/ReShade_Setup_6.8.0_Addon.exe";
  for (const danger of ["safe", "uncommon", "content", "unwanted", "dangerous", "unsigned"]) {
    const { emit, native, downloadActions } = await browser(false);
    let suggested = false;
    emit("download", { id: 7, url, finalUrl: url, filename: "ReShade_Setup_6.8.0_Addon.exe", danger }, () => { suggested = true; });
    for (let i = 0; i < 20 && !downloadActions.some(([action]) => action === "cancel"); i++)
      await new Promise((resolve) => setImmediate(resolve));
    const handoff = native.map(([, entry]) => entry).find((entry) => entry.url === url);
    assert.ok(handoff, danger);
    assert.equal(handoff.cookies, "");
    assert.equal(handoff.browserCredentialsUnavailable, true);
    assert.equal(Boolean(handoff.browserWarning), danger !== "safe");
    assert.ok(downloadActions.some(([action, id]) => action === "cancel" && id === 7));
    assert.equal(suggested, false, "do not release the download back to the browser");
  }
});

test("Firefox captures uncertain browser sessions without copying cookies", async () => {
  const { emit, native, downloadActions } = await browser(true);
  const url = "https://files.example.test/report.zip";
  await Promise.all(emit("download", { id: 4, url, filename: "report.zip", danger: "safe" }));
  const handoff = native.map(([, entry]) => entry).find((entry) => entry.url === url);
  assert.equal(handoff.cookies, "");
  assert.equal(handoff.browserCredentialsUnavailable, true);
  assert.ok(downloadActions.some(([action, id]) => action === "cancel" && id === 4));
  assert.ok(!downloadActions.some(([action]) => action === "resume"));
});

test("selection import sends its link list without the page's cookies", async () => {
  const referrer = "https://files.example.test/reports/";
  const links = ["https://files.example.test/shared/example.zip", "https://static.example.test/report.zip"];
  let storeReads = 0;
  const { script, native } = await browser(false, { links,
    listCookies: async () => { storeReads++; return [{ name: "format", value: "standard", path: "/reports" }]; } });
  await script.menuClicked({ menuItemId: "mdm-selected", pageUrl: referrer, frameId: 1 }, { id: 7 });
  const [list] = native.map(([, message]) => message).filter(({ links }) => links);
  assert.deepEqual(list.links, links);
  assert.equal(list.referrer, referrer);
  assert.equal(list.cookies, undefined);
  assert.equal(storeReads, 0);
});

test("extension size limit leaves valid native messages intact", async () => {
  const { script, native } = await browser(false);
  const direct = { url: "https://files.example.test/archive.zip", filename: "archive.zip" };
  assert.equal((await script.native(direct)).ok, true);
  const calls = native.length;
  const tooLarge = await script.native({ ...direct, title: "a".repeat(1 << 20) });
  assert.equal(tooLarge.why, "too-large");
  assert.equal(native.length, calls);
});

test("local settings reads and downloads use their designated destination", async () => {
  const { script, native } = await browser(false);
  const paired = { url: "https://companion.example.test/", token: "test-pairing" };
  const submissions = [];
  script.remoteTarget = async () => paired;
  script.remoteSend = async (target, url) => {
    submissions.push({ target, url });
    return { ok: true };
  };

  const page = "https://files.example.test/videos";
  assert.equal(await script.panelOn(page), true);
  assert.ok(native.some(([, message]) => message.panel === true && message.url === page));
  assert.equal(submissions.length, 0);

  const download = "https://files.example.test/archive.zip";
  assert.equal((await script.submitDownload({ url: download })).ok, true);
  assert.deepEqual(submissions, [{ target: paired, url: download }]);
  assert.equal((await script.submitDownload({ url: download, private: true })).ok, true);
  assert.ok(native.some(([, message]) => message.private === true && message.url === download));
  assert.equal(submissions.length, 1);
});

test("media manifests use the decoded byte limit even without a reliable length header", async () => {
  const { script } = await browser(false);
  script.AbortController = AbortController;
  const item = { url: "https://stream.example.test/index.m3u8", kind: "hls" };
  const utf8 = new TextEncoder();
  const sample = utf8.encode("#EXTM3U\n#EXTINF:6.5,Example\nclip.ts\n#EXT-X-ENDLIST\n");
  let signal;
  function response(chunks, length) {
    const body = new ReadableStream({
      start(controller) {
        for (const chunk of chunks) controller.enqueue(chunk);
        controller.close();
      },
    });
    script.fetch = async (_url, options) => {
      signal = options.signal;
      return { ok: true, headers: new Headers(length === null ? {} : { "Content-Length": length }), body };
    };
    return body;
  }
  const chunked = response([sample.subarray(0, 3), sample.subarray(3)], null);
  assert.equal((await script.probe(item)).duration, 6.5);
  assert.equal(chunked.locked, false);
  assert.equal(signal.aborted, false);

  const limit = 2 << 20;
  const padded = new Uint8Array(limit - sample.length).fill(32);
  const full = response([sample, padded], null);
  assert.equal((await script.probe(item)).duration, 6.5);
  assert.equal(full.locked, false);

  const oversized = response([sample, padded, Uint8Array.of(32)], String(sample.length));
  assert.equal((await script.probe(item)).failed, true);
  assert.equal(oversized.locked, false);
  assert.equal(signal.aborted, true);

  const advertisedOversize = response([sample], String(limit + 1));
  assert.equal((await script.probe(item)).failed, true);
  assert.equal(advertisedOversize.locked, false);
  assert.equal(signal.aborted, true);
});

test("one media manifest deadline cancels the header and body waits", async () => {
  const { script } = await browser(false);
  script.AbortController = AbortController;
  const item = { url: "https://stream.example.test/index.mpd", kind: "dash" };
  for (const waitFor of ["headers", "body"]) {
    let expire;
    let cleared = false;
    let signal;
    let body;
    script.setTimeout = (callback) => {
      assert.equal(expire, undefined);
      expire = callback;
      return 1;
    };
    script.clearTimeout = (id) => {
      assert.equal(id, 1);
      cleared = true;
    };
    script.fetch = (_url, options) => {
      signal = options.signal;
      if (waitFor === "headers") {
        return new Promise((_, reject) => signal.addEventListener("abort", () => reject(signal.reason), { once: true }));
      }
      body = new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("<MPD"));
          signal.addEventListener("abort", () => controller.error(signal.reason), { once: true });
        },
      });
      return Promise.resolve({ ok: true, headers: new Headers(), body });
    };
    const reading = script.probe(item);
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(signal.aborted, false);
    if (body) assert.equal(body.locked, true);
    expire();
    assert.equal((await reading).failed, true);
    assert.equal(signal.aborted, true);
    assert.equal(cleared, true);
    if (body) assert.equal(body.locked, false);
  }
});

