import { invoke } from "@tauri-apps/api/core";

const extra = new Set(["auralis-update-presentation", "auralis-download-columns", "auralis-setup-auto-close"]);
const allowed = (key: string) => key.startsWith("mh-glass-") || extra.has(key);

export function appearanceBackup(): Record<string, string> {
  const result: Record<string, string> = {};
  for (let index = 0; index < localStorage.length; index++) {
    const key = localStorage.key(index);
    if (key && allowed(key)) {
      const value = localStorage.getItem(key);
      if (value !== null) result[key] = value;
    }
  }
  return result;
}

function applyAppearanceBackup(data: Record<string, unknown>, complete = false) {
  const entries = new Map<string, string>();
  const encoder = new TextEncoder();
  let size = 0;
  for (const [key, value] of Object.entries(data)) {
    if (!allowed(key)) continue;
    if (typeof value !== "string" || value.length > 2 * 1024 * 1024) {
      throw Error(`Invalid or oversized saved preference: ${key}`);
    }
    size += encoder.encode(key + value).length;
    if (size > 3 * 1024 * 1024) throw Error("Appearance preferences are too large to restore.");
    entries.set(key, value);
  }

  const keys = new Set(entries.keys());
  if (complete) {
    for (const key of Object.keys(appearanceBackup())) keys.add(key);
  }
  const previous = new Map([...keys].map(key => [key, localStorage.getItem(key)]));
  try {
    for (const key of keys) {
      if (!entries.has(key)) localStorage.removeItem(key);
    }
    for (const [key, value] of entries) localStorage.setItem(key, value);
  } catch (error) {
    for (const key of keys) {
      try { localStorage.removeItem(key); }
      catch { /* Keep the original storage error. */ }
    }
    for (const [key, value] of previous) {
      if (value !== null) {
        try { localStorage.setItem(key, value); }
        catch { /* Keep the original storage error. */ }
      }
    }
    throw error;
  }
  window.dispatchEvent(new StorageEvent("storage"));
}

export async function savePreferences() {
  return invoke<string | null>("export_preferences", { ui: appearanceBackup() });
}

export async function restorePreferences() {
  const data = await invoke<Record<string, unknown> | null>("import_preferences");
  if (!data) return false;
  applyAppearanceBackup(data);
  return true;
}

type ArchiveRestore = {
  path: string;
  restored_to?: string;
  ui?: Record<string, unknown>;
  ui_complete?: boolean;
  warning?: string;
  appearanceError?: string;
};

export async function saveDownloadBackup() {
  return invoke<{ path: string } | null>("export_full_backup", { ui: appearanceBackup() });
}

export async function restoreDownloadBackup(): Promise<ArchiveRestore | null> {
  const result = await invoke<ArchiveRestore | null>("import_full_backup");
  if (!result?.ui) return result;
  try {
    applyAppearanceBackup(result.ui, result.ui_complete === true);
    return result;
  } catch (error) {
    return { ...result, appearanceError: String(error) };
  }
}
