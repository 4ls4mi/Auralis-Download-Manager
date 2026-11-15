import { convertFileSrc } from "@tauri-apps/api/core";
import { getCurrentWindow, Effect, EffectState } from "@tauri-apps/api/window";
import type { ResizeDirection } from "@tauri-apps/api/window";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { useEffect, useState, createContext, useContext } from "react";
import type { CSSProperties, ReactNode } from "react";
import { AppWindow, Maximize2, Minus, X } from "lucide-react";

export type Status = "Queued" | "Downloading" | "Stopped" | "Complete" | "Error";
export type Download = {
  id: number; file: string; url: string; path: string; status: Status;
  size: number | null; downloaded: number; speed: number; added: string | null;
  category: string; error?: string | null
};
export type Queue = { name: string; running: boolean; ids: number[] };
export type Dashboard = {
  downloads: Download[]; speed: number; queues: Queue[];
  categories: { name: string; key: string }[]; free?: number | null
};
export type Theme = { id: string; name: string; accent: string; secondary: string; rgb: string };
export const themes: Theme[] = [
  { id: "plexo", name: "Crystal Teal", accent: "#0fe6d5", secondary: "#4b9cfc", rgb: "15,230,213" },
  { id: "ocean", name: "Glacier Blue", accent: "#4bb8fa", secondary: "#7c83f8", rgb: "75,184,250" },
  { id: "purple", name: "Amethyst", accent: "#b68aff", secondary: "#f078d5", rgb: "182,138,255" },
  { id: "pink", name: "Ruby Ice", accent: "#f86d9e", secondary: "#ffad75", rgb: "248,109,158" },
  { id: "gold", name: "Amber Frost", accent: "#ffbb62", secondary: "#ff7c73", rgb: "255,187,98" },
  { id: "green", name: "Emerald", accent: "#43e7ae", secondary: "#70c9fc", rgb: "67,231,174" },
  { id: "silver", name: "Graphite", accent: "#b1c9e0", secondary: "#70a2cc", rgb: "177,201,224" },
  { id: "navy", name: "Deep Indigo", accent: "#748cff", secondary: "#a679fd", rgb: "116,140,255" }
];
export type BackgroundMode = "desktop" | "wallpaper" | "solid";
export type Appearance = {
  theme: string; wallMain: string; wallDetail: string; mainMode: BackgroundMode;
  detailMode: BackgroundMode; dim: number; opacity: number; blur: number;
  acrylic: boolean; autoPopups: boolean; uiScale: number
};
const key = "mh-glass-";
const stored = (name: string, fallback: string) => {
  try { return localStorage.getItem(key + name) ?? fallback }
  catch { return fallback }
};
export function loadAppearance(): Appearance {
  return {
    theme: stored("theme", "plexo"),
    wallMain: stored("wall-main", ""), wallDetail: stored("wall-detail", ""),
    mainMode: stored("back-main", "wallpaper") as BackgroundMode,
    detailMode: stored("back-details", "wallpaper") as BackgroundMode,
    dim: Number(stored("dim", "26")), opacity: Number(stored("opacity", "66")),
    blur: Number(stored("blur", "3")), acrylic: stored("acrylic", "true") === "true",
    autoPopups: stored("auto-popups", "true") === "true",
    uiScale: Number(stored("ui-scale", "100"))
  };
}
const keys: Record<keyof Appearance, string> = {
  theme: "theme", wallMain: "wall-main", wallDetail: "wall-detail",
  mainMode: "back-main", detailMode: "back-details", dim: "dim",
  opacity: "opacity", blur: "blur", acrylic: "acrylic",
  autoPopups: "auto-popups", uiScale: "ui-scale"
};
type AppearanceValue = {
  appearance: Appearance; theme: Theme;
  set: <K extends keyof Appearance>(key: K, value: Appearance[K]) => void
};
const Context = createContext<AppearanceValue | null>(null);
export function useCrystal() {
  const ctx = useContext(Context);
  if (!ctx) throw Error("CrystalProvider missing");
  return ctx;
}
export function CrystalProvider({ children }: { children: ReactNode }) {
  const [appearance, setAppearance] = useState(loadAppearance);
  useEffect(() => {
    const listener = (e: StorageEvent) => {
      if (!e.key || e.key.startsWith(key)) setAppearance(loadAppearance());
    };
    window.addEventListener("storage", listener);
    return () => window.removeEventListener("storage", listener);
  }, []);
  const set = <K extends keyof Appearance>(name: K, value: Appearance[K]) => {
    localStorage.setItem(key + keys[name], String(value));
    setAppearance(prev => ({ ...prev, [name]: value }));
  };
  const theme = themes.find(t => t.id === appearance.theme) ?? themes[0];
  return <Context.Provider value={{ appearance, set, theme }}>{children}</Context.Provider>;
}
export function hue(hex: string) {
  const c = hex.match(/[0-9a-f]{2}/gi)?.map(x => parseInt(x, 16) / 255) ?? [0, .8, .75];
  const max = Math.max(...c), min = Math.min(...c), d = max - min;
  if (!d) return 180;
  const idx = c.indexOf(max);
  const h = idx === 0 ? (c[1] - c[2]) / d + (c[1] < c[2] ? 6 : 0)
    : idx === 1 ? (c[2] - c[0]) / d + 2 : (c[0] - c[1]) / d + 4;
  return h * 60;
}
export function progressGradient(percent: number, accent: string) {
  const base = hue(accent), spread = 14 + Math.min(100, Math.max(0, percent)) * 2.05;
  const a = `hsl(${base.toFixed(1)} 92% 54%)`;
  const b = `hsl(${((base + spread * .57) % 360).toFixed(1)} 90% 57%)`;
  const c = `hsl(${((base + spread) % 360).toFixed(1)} 91% 61%)`;
  return `linear-gradient(90deg, ${a}, ${b} 53%, ${c})`;
}
export function pct(d: Download) {
  return d.size && d.size > 0 ? Math.max(0, Math.min(100, 100 * d.downloaded / d.size))
    : d.status === "Complete" ? 100 : 0;
}
export function units(value: number | null | undefined) {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  const x = value < 1024 ? 0 : Math.min(4, Math.floor(Math.log(value) / Math.log(1024)));
  return (value / 1024 ** x).toFixed(x === 0 ? 0 : 1) + " " + ["B", "KB", "MB", "GB", "TB"][x];
}
export const rate = (n: number) => units(n) + "/s";
export function timeLeft(d: Download) {
  if (d.status !== "Downloading" || !d.size || d.speed <= 0) return "—";
  const s = Math.ceil(Math.max(0, d.size - d.downloaded) / d.speed);
  return s < 60 ? s + "s" : s < 3600 ? Math.floor(s / 60) + "m " + s % 60 + "s"
    : Math.floor(s / 3600) + "h " + Math.floor(s % 3600 / 60) + "m";
}
export function GradientBar({ percent, blocks = 17, showLabel = false }: {
  percent: number; blocks?: number; showLabel?: boolean
}) {
  const { theme } = useCrystal();
  const fill = Math.max(0, Math.min(100, percent));
  return <div className="cg-progress">
    <div className="cg-blocks" aria-label={`${Math.round(fill)} percent completed`}>
      {Array.from({ length: blocks }, (_, i) => {
        const on = i / blocks * 100 < fill;
        const color = `hsl(${(hue(theme.accent) + (i + 1) / blocks * (15 + fill * 2.05)) % 360} 87% 57%)`;
        return <i key={i} className={on ? "lit" : ""} style={{ background: on ? color : undefined }} />;
      })}
    </div>
    {showLabel && <strong>{fill.toFixed(0)}%</strong>}
  </div>;
}
export function FlowMatrix({ percent, count = 168 }: { percent: number; count?: number }) {
  const { theme } = useCrystal();
  return <div className="cg-matrix" role="img"
    aria-label={`${Math.round(percent)}% complete. Decorative color-flow blocks, not actual connections.`}>
    {Array.from({ length: count }, (_, i) => {
      const on = i / count * 100 < percent;
      const h = (hue(theme.accent) + i / count * (15 + percent * 2.05)) % 360;
      return <i key={i} className={on ? "lit" : ""}
        style={on ? { background: `hsl(${h.toFixed(1)} 90% 57%)`, boxShadow: `0 0 9px hsla(${h.toFixed(1)},100%,60%,.24)` } : {}} />;
    })}
  </div>;
}
export function SpeedGraph({ values }: { values: number[] }) {
  const seq = values.length > 1 ? values : [0, 0], peak = Math.max(1, ...seq) * 1.12;
  const line = seq.map((v, i) => (i / (seq.length - 1) * 100).toFixed(2) + "," + (58 - v / peak * 48).toFixed(2)).join(" ");
  return <svg className="cg-graph" viewBox="0 0 100 65" preserveAspectRatio="none"
    role="img" aria-label="Actual recent transfer speed">
    <defs><linearGradient id="cg-fill" x1="0" x2="0" y1="0" y2="1">
      <stop stopColor="var(--accent)" stopOpacity=".22" /><stop offset="1" stopColor="var(--accent)" stopOpacity="0" />
    </linearGradient></defs>
    {[15, 37, 57].map(y => <line key={y} x1="0" x2="100" y1={y} y2={y}
      stroke="rgba(180,227,242,.13)" strokeWidth=".35" />)}
    <polygon points={`0,65 ${line} 100,65`} fill="url(#cg-fill)" />
    <polyline points={line} stroke="var(--accent)" strokeWidth="1.65" fill="none"
      strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
  </svg>;
}
const directions = ["North", "South", "East", "West", "NorthEast", "NorthWest", "SouthEast", "SouthWest"] as const;
export function ResizeGrips() {
  return <div className="cg-grips">{directions.map(direction =>
    <div key={direction} className={`cg-resize cg-${direction.toLowerCase()}`}
      onMouseDown={e => { e.preventDefault(); void getCurrentWindow().startResizeDragging(direction as ResizeDirection); }} />
  )}</div>;
}
export function WindowButtons({ noMax = false }: { noMax?: boolean }) {
  const w = getCurrentWindow();
  return <div className="cg-winbuttons">
    <button title="Minimize" onClick={() => void w.minimize()}><Minus size={17} /></button>
    {!noMax && <button title="Maximize or restore" onClick={() => void w.toggleMaximize()}><Maximize2 size={16} /></button>}
    <button className="close" title="Close" onClick={() => void w.close()}><X size={20} /></button>
  </div>;
}
export function WindowTop({ title, children, noMax = false }: {
  title: string; children?: ReactNode; noMax?: boolean
}) {
  return <header className="cg-window-top">
    <div className="cg-title" data-tauri-drag-region
      onMouseDown={e => { if (e.button === 0 && e.target === e.currentTarget) void getCurrentWindow().startDragging(); }}>
      <span className="cg-logo" data-tauri-drag-region><AppWindow size={18} /></span>
      <span data-tauri-drag-region>{title}</span>
    </div>{children}<WindowButtons noMax={noMax} />
  </header>;
}
export function CrystalWindow({ children, target = "main" }: {
  children: ReactNode; target?: "main" | "details"
}) {
  const { appearance, theme } = useCrystal();
  const main = target === "main", mode = main ? appearance.mainMode : appearance.detailMode;
  const path = main ? appearance.wallMain : (appearance.wallDetail || appearance.wallMain);
  const src = path ? convertFileSrc(path) : "/alpine.svg";
  const video = /\.(mp4|webm|mov|m4v)$/i.test(path);
  useEffect(() => {
    const w = getCurrentWindow();
    if (mode === "desktop" && appearance.acrylic)
      void w.setEffects({ effects: [Effect.Acrylic], state: EffectState.Active }).catch(() => undefined);
    else void w.clearEffects().catch(() => undefined);
  }, [mode, appearance.acrylic]);
  const style = {
    "--accent": theme.accent, "--accent-secondary": theme.secondary,
    "--accent-rgb": theme.rgb,
    "--panel-opacity": Math.min(.94, Math.max(.45, appearance.opacity / 100)),
    "--crystal-blur": appearance.blur + "px",
    "--ui-scale": appearance.uiScale / 100
  } as CSSProperties;
  return <div className={`cg-window cg-mode-${mode}`} style={style}>
    {mode === "wallpaper" && <div className="cg-wallpaper">
      {video ? <video key={src} autoPlay loop muted playsInline src={src} /> :
        <div style={{ backgroundImage: `url("${src}")` }} />}
      <span style={{ background: `rgba(3,9,19,${appearance.dim / 100})` }} />
    </div>}
    {mode === "solid" && <div className="cg-solid" />}
    <div className="cg-content">{children}</div>
    <ResizeGrips />
  </div>;
}
export function openWindow(label: string, url: string, width: number, height: number) {
  void WebviewWindow.getByLabel(label).then(w => {
    if (w) { void w.unminimize(); void w.show(); void w.setFocus(); return; }
    new WebviewWindow(label, {
      url, title: "Mister Hybrid Glass", width, height, minWidth: Math.min(540, width),
      minHeight: Math.min(420, height), center: true, decorations: false, resizable: true,
      transparent: true, shadow: false, backgroundColor: "#00000000"
    });
  }).catch(e => { window.alert("Couldn't open window: " + String(e)); });
}
