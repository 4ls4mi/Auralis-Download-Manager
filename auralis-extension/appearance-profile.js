// Shared by our extension pages, background and isolated video controls.
(() => {
  if (globalThis.__auralisAppearanceProfile) return;
  const choiceKey = "browserAppearanceChoice";
  const cacheKey = "browserAppearance";
  const paletteRoles = {
    background: "--bg", surface: "--field", text: "--text", muted: "--muted", accent: "--accent",
    border: "--edge", positive: "--ok", caution: "--warn", destructive: "--bad",
  };

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

  function selectedTheme(snapshot, choice) {
    if (choice === "browser" || !snapshot) return null;
    if (typeof choice === "string" && choice.startsWith("theme:")) {
      const id = choice.slice(6);
      const chosen = snapshot.themes.find(theme => theme.id === id);
      if (chosen) return chosen;
    }
    return snapshot.current;
  }

  globalThis.__auralisAppearanceProfile = Object.freeze({
    choiceKey, cacheKey, paletteRoles: Object.freeze(paletteRoles), readTheme,
    readSnapshot, selectedTheme, luminance,
  });
})();
