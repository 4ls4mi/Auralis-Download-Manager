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

async function browser(firefox) {
  const events = new Map();
  const native = [];
  const saved = {};
  const event = (name) => ({ addListener(fn) {
    if (!events.has(name)) events.set(name, []);
    events.get(name).push(fn);
  } });
  const eventsFor = (prefix, names) => Object.fromEntries(names.map((name) => [name, event(prefix + name)]));
  const options = { ok: true, version: "0.5.2", types: "ZIP", capture: true };
  const script = vm.createContext({
    URL, URLSearchParams, TextDecoder, console, setTimeout, clearTimeout,
    navigator: { userAgent: "Auralis fixture" },
    browser: {
      downloads: firefox ? { onCreated: event("download") } : { onDeterminingFilename: event("download") },
      storage: { local: { get: async (keys) => Array.isArray(keys) ? saved : { ...keys, ...saved },
        set: async (values) => Object.assign(saved, values) }, onChanged: event("storage") },
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
      action: { setBadgeText: async () => {}, setBadgeBackgroundColor: async () => {}, setTitle: async () => {} },
      permissions: { contains: async () => true },
      cookies: { getAll: async () => [
        { name: "format", value: "standard", domain: "stream.example.test", path: "/videos", hostOnly: true, secure: true },
        { name: "preference", value: "other", domain: "stream.example.test", path: "/", hostOnly: true, secure: true },
      ] },
    },
  });
  vm.runInContext(appearance, script);
  vm.runInContext(source, script);
  // Allow startup to cache rules before running the isolated scenarios.
  await new Promise((resolve) => setImmediate(resolve));
  return { script, native,
    emit(name, details) { for (const fn of events.get(name) ?? []) fn(details); },
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

test("automatic handoff leaves browser-flagged downloads in the browser", async () => {
  const { script } = await browser(false);
  const url = "https://files.example.test/report.zip";
  assert.equal(await script.candidate({ url, danger: "content" }, url), null);
  assert.ok(await script.candidate({ url, danger: "safe" }, url));
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

test("extension size limit leaves valid native messages intact", async () => {
  const { script, native } = await browser(false);
  const direct = { url: "https://files.example.test/archive.zip", filename: "archive.zip" };
  assert.equal((await script.native(direct)).ok, true);
  const calls = native.length;
  const tooLarge = await script.native({ ...direct, title: "a".repeat(1 << 20) });
  assert.equal(tooLarge.why, "too-large");
  assert.equal(native.length, calls);
});
