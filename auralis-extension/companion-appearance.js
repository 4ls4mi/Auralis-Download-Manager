// The style nodes live in closed shadow trees. No appearance names, file paths,
// storage values or custom properties are written onto the page's own elements.
(() => {
  if (globalThis.__auralisCompanionAppearance) return;
  const ext = globalThis.browser ?? globalThis.chrome;
  const model = globalThis.__auralisAppearanceProfile;
  const selectors = ".control,.pill,.menu,.tip,.guide";
  const dark = {
    background: "#102036", surface: "#19324c", text: "#f4f8ff", muted: "#c8d7e8",
    accent: "#8deaff", border: "#57748f", positive: "#74f6bf", caution: "#ffe19c", destructive: "#ffacb9",
  };
  const light = {
    background: "#e8f2ff", surface: "#f4f8ff", text: "#152841", muted: "#425d77",
    accent: "#146c89", border: "#9cb5d0", positive: "#087c59", caution: "#875200", destructive: "#b92f45",
  };
  const variables = (palette, isLight, radius, opaque) => {
    const inkFor = (color) => model.luminance(color) > .179 ? "#08090c" : "#ffffff";
    const accent = model.luminance(palette.accent);
    const surface = model.luminance(palette.surface);
    const contrast = (Math.max(accent, surface) + .05) / (Math.min(accent, surface) + .05);
    return `${selectors}{
      ${Object.entries(palette).map(([key, value]) => `--ac-${key}:${value};`).join("")}
      --ac-radius:${radius}px;
      --ac-accent-ink:${inkFor(palette.accent)};
      --ac-positive-ink:${inkFor(palette.positive)};
      --ac-caution-ink:${inkFor(palette.caution)};
      --ac-destructive-ink:${inkFor(palette.destructive)};
      --ac-link:${contrast >= 4.5 ? palette.accent : palette.text};
      --ac-border-soft:color-mix(in srgb,var(--ac-border) 40%,transparent);
      --ac-hover:color-mix(in srgb,var(--ac-accent) 18%,var(--ac-surface));
      --ac-selected:color-mix(in srgb,var(--ac-accent) 27%,var(--ac-surface));
      --ac-panel:${opaque ? "var(--ac-background)" : "color-mix(in srgb,var(--ac-background) 94%,transparent)"};
      --ac-control:${opaque ? "var(--ac-surface)" : "linear-gradient(145deg,var(--ac-hover),var(--ac-background))"};
      --ac-blur:${opaque ? "none" : "blur(16px) saturate(125%)"};
      color-scheme:${isLight ? "light" : "dark"};
    }`;
  };
  const fallback = variables(dark, false, 10, false)
    + `@media (prefers-color-scheme:light){${variables(light, true, 10, false)}}`;
  const styles = new Set();
  let active = 0;
  let stylesheet = fallback;
  let timer;
  let pending = false;
  let queued = false;

  let shared;
  try {
    shared = new CSSStyleSheet();
    shared.replaceSync(stylesheet);
  } catch {
    shared = null;
  }

  function attach(root) {
    if (shared) {
      try {
        root.adoptedStyleSheets = [...root.adoptedStyleSheets, shared];
        return () => { root.adoptedStyleSheets = root.adoptedStyleSheets.filter(sheet => sheet !== shared); };
      } catch {
        // Older webviews use a style node inside the same closed root.
      }
    }
    const style = document.createElement("style");
    style.textContent = stylesheet;
    root.append(style);
    styles.add(style);
    return () => {
      styles.delete(style);
      style.remove();
    };
  }

  function apply(palette) {
    const profile = palette && model.readTheme({ ...palette, id: "companion", label: "Auralis" });
    const next = profile ? variables(profile.colors, profile.light, profile.radius, profile.opaque) : fallback;
    if (stylesheet === next) return;
    stylesheet = next;
    shared?.replaceSync(stylesheet);
    for (const style of styles) style.textContent = stylesheet;
  }

  async function refresh() {
    clearTimeout(timer);
    if (!active || document.hidden || !ext.runtime?.id) return;
    if (pending) {
      queued = true;
      return;
    }
    pending = true;
    try {
      const reply = await ext.runtime.sendMessage({ type: "companion-appearance" });
      if (reply?.ok) apply(reply.palette);
    } catch {
      // Keep the last valid palette if the extension or desktop helper is reconnecting.
    } finally {
      pending = false;
      if (queued) {
        queued = false;
        refresh();
      } else if (active && !document.hidden && ext.runtime?.id) {
        timer = setTimeout(refresh, 2500);
      }
    }
  }

  function activate() {
    if (++active === 1) refresh();
    let released = false;
    return () => {
      if (!released && --active === 0) clearTimeout(timer);
      released = true;
    };
  }

  ext.storage?.onChanged?.addListener((change, area) => {
    if (area === "local" && (change[model.choiceKey] || change[model.cacheKey])) refresh();
  });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) clearTimeout(timer);
    else refresh();
  });
  globalThis.__auralisCompanionAppearance = Object.freeze({ attach, activate });
})();
