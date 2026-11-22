(() => {
  const ext = globalThis.browser ?? globalThis.chrome;
  const root = document.documentElement;
  const control = document.getElementById("appearance-choice");
  const note = document.getElementById("appearance-note");
  const storage = ext.storage.local;
  const text = (key, ...args) => ext.i18n.getMessage(key, args) || key;
  const { choiceKey, cacheKey, paletteRoles, readSnapshot, luminance } = globalThis.__auralisAppearanceProfile;
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
