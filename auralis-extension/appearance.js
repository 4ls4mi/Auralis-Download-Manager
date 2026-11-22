(() => {
  const ext = globalThis.browser ?? globalThis.chrome;
  const root = document.documentElement;
  const control = document.getElementById("appearance-choice");
  const note = document.getElementById("appearance-note");
  const storage = ext.storage.local;
  const text = (key, ...args) => ext.i18n.getMessage(key, args) || key;
  const choiceKey = "browserAppearanceChoice";
  const cacheKey = "browserAppearance";
  const paletteRoles = {
    background: "--bg", surface: "--field", text: "--text", muted: "--muted", accent: "--accent",
    border: "--edge", positive: "--ok", caution: "--warn", destructive: "--bad",
  };
  let choice = "desktop";
  let cache;
  let lastOptions;
  let serial;
  let available = false;
  let checking = false;
  let nextCheck;

  root.lang = ext.i18n.getUILanguage();
  root.dir = text("@@bidi_dir") === "rtl" ? "rtl" : "ltr";
  for (const node of document.querySelectorAll("[data-appearance-text]")) {
    node.textContent = text(node.dataset.appearanceText);
  }

  function readTheme(profile) {
    if (!profile || typeof profile.id !== "string" || !/^[a-z0-9_-]{1,96}$/i.test(profile.id)
      || typeof profile.label !== "string" || !profile.label.trim() || profile.label.length > 100
      || /[\u0000-\u001f\u007f-\u009f]/.test(profile.label) || typeof profile.light !== "boolean"
      || (profile.opaque !== undefined && typeof profile.opaque !== "boolean")
      || (profile.radius !== undefined && (!Number.isInteger(profile.radius) || profile.radius < 0 || profile.radius > 24))) return null;
    const colors = {};
    for (const role of Object.keys(paletteRoles)) {
      const color = profile.colors?.[role];
      if (typeof color !== "string" || !/^#[a-f0-9]{6}$/i.test(color)) return null;
      colors[role] = color.toLowerCase();
    }
    return { id: profile.id, label: profile.label, light: profile.light, colors,
      radius: profile.radius ?? 9, opaque: profile.opaque ?? true };
  }

  function readSnapshot(value) {
    if (!value || value.version !== 1 || !Array.isArray(value.themes) || value.themes.length > 64) return null;
    const current = readTheme(value.current);
    if (!current) return null;
    const themes = new Map();
    for (const profile of value.themes) {
      const theme = readTheme(profile);
      if (!theme) return null;
      themes.set(theme.id, theme);
    }
    return { version: 1, current, themes: [...themes.values()] };
  }

  function luminance(color) {
    const linear = (position) => {
      const channel = parseInt(color.slice(position, position + 2), 16) / 255;
      return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * linear(1) + 0.7152 * linear(3) + 0.0722 * linear(5);
  }

  function setStyles(theme) {
    for (const [role, name] of Object.entries(paletteRoles)) {
      if (theme) root.style.setProperty(name, theme.colors[role]);
      else root.style.removeProperty(name);
    }
    if (theme) {
      root.dataset.appearance = theme.light ? "light" : "dark";
      root.dataset.appearanceOpaque = String(theme.opaque);
      root.style.setProperty("--radius", theme.radius + "px");
      root.style.setProperty("--accent-text", luminance(theme.colors.accent) > 0.179 ? "#08090c" : "#ffffff");
      const accent = luminance(theme.colors.accent);
      const bg = luminance(theme.colors.background);
      const contrast = (Math.max(accent, bg) + 0.05) / (Math.min(accent, bg) + 0.05);
      root.style.setProperty("--link", contrast >= 4.5 ? theme.colors.accent : theme.colors.text);
    } else {
      delete root.dataset.appearance;
      delete root.dataset.appearanceOpaque;
      for (const name of ["--radius", "--accent-text", "--link"]) root.style.removeProperty(name);
    }
  }

  function render() {
    const themes = new Map((cache?.themes || []).map((theme) => ["theme:" + theme.id, theme]));
    if (cache && !themes.has("theme:" + cache.current.id)) {
      themes.set("theme:" + cache.current.id, cache.current);
    }
    const selection = choice === "browser" || themes.has(choice) ? choice : "desktop";
    const profile = selection === "desktop" ? cache?.current : themes.get(selection);
    const list = [
      ["desktop", text("appearance_follow")], ["browser", text("appearance_system")],
      ...Array.from(themes, ([id, theme]) => [id, theme.label]),
    ];
    const options = JSON.stringify(list);
    if (lastOptions !== options) {
      control.replaceChildren(...list.map(([value, label]) => {
        const option = document.createElement("option");
        option.value = value;
        option.textContent = label;
        return option;
      }));
      lastOptions = options;
    }
    control.value = selection;
    setStyles(profile);
    const description = selection === "desktop"
      ? (cache ? text(available ? "appearance_current" : "appearance_cached", cache.current.label)
        : text("appearance_unavailable"))
      : "";
    if (note.textContent !== description) note.textContent = description;
    note.hidden = !description;
  }

  async function refresh() {
    clearTimeout(nextCheck);
    if (checking || document.hidden) return;
    checking = true;
    try {
      const response = await ext.runtime.sendMessage({ type: "desktop-appearance" }).catch(() => null);
      const fresh = readSnapshot(response?.appearance);
      available = Boolean(response?.ok && fresh);
      if (available) {
        cache = fresh;
        const data = JSON.stringify(cache);
        if (data !== serial) {
          serial = data;
          storage.set({ [cacheKey]: cache }).catch(() => {});
        }
      }
      render();
    } finally {
      checking = false;
      if (!document.hidden) nextCheck = setTimeout(refresh, available ? 2500 : 8000);
    }
  }

  function receive(values) {
    if (Object.hasOwn(values, choiceKey)) choice = values[choiceKey] || "desktop";
    if (Object.hasOwn(values, cacheKey)) {
      const saved = readSnapshot(values[cacheKey]);
      if (saved) {
        cache = saved;
        serial = JSON.stringify(saved);
      }
    }
    render();
  }

  control.addEventListener("change", () => {
    choice = control.value;
    render();
    storage.set({ [choiceKey]: choice }).catch(() => {});
  });
  ext.storage.onChanged.addListener((changes, area) => {
    if (area !== "local" || !(changes[choiceKey] || changes[cacheKey])) return;
    const values = {};
    for (const key of [choiceKey, cacheKey]) {
      if (changes[key]) values[key] = changes[key].newValue;
    }
    receive(values);
  });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) clearTimeout(nextCheck);
    else refresh();
  });
  storage.get([choiceKey, cacheKey]).then(receive, render).finally(refresh);
})();
