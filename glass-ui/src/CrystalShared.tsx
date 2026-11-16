import { convertFileSrc } from "@tauri-apps/api/core";
import { getCurrentWindow, Effect, EffectState } from "@tauri-apps/api/window";
type ResizeDirection = Parameters<ReturnType<typeof getCurrentWindow>["startResizeDragging"]>[0];
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { useEffect, useState, useId, createContext, useContext } from "react";
import type { CSSProperties, ReactNode } from "react";
import { AppWindow, Maximize2, Minus, X } from "lucide-react";

export type Status = "Queued" | "Downloading" | "Stopped" | "Complete" | "Error";
export type Download = {
  id: number; file: string; url: string; path: string; status: Status;
  size: number | null; downloaded: number; speed: number; added: string | null;
  category: string; error?: string | null
};
export type Queue = { name: string; running: boolean; ids: number[] };
export type Segment = { start: number; cursor: number; end: number };
export type Connection = { id: number; downloaded: number; speed: number; state: string };
export type DownloadVisual = {
  id: number; segments: Segment[]; connections: Connection[]; resumable: boolean | null;
  server: {hostname:string|null;ip:string|null;country_code:string|null;rtt_ms:number|null;cdn:string|null;proxied:boolean};
  last_try:string|null;added:string|null;referer:string|null;page:string|null;
  description:string;category:string;is_torrent:boolean
};
export type VisualDashboard = {downloads:DownloadVisual[]};

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
  acrylic: boolean; autoPopups: boolean; uiScale: number;
  lightMode: boolean; fontFamily: string; fontSize: number
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
    mainMode: stored("back-main", "desktop") as BackgroundMode,
    detailMode: stored("back-details", "desktop") as BackgroundMode,
    dim: Number(stored("dim", "26")), opacity: Number(stored("opacity", "77")),
    blur: Number(stored("blur", "3")), acrylic: stored("acrylic", "false") === "true",
    autoPopups: stored("auto-popups", "true") === "true",
    uiScale: Number(stored("ui-scale", "100")),
    lightMode: stored("light-mode", "false") === "true",
    fontFamily: stored("font-family","Segoe UI"),fontSize:Number(stored("font-size","12"))
  };
}
const keys: Record<keyof Appearance, string> = {
  theme: "theme", wallMain: "wall-main", wallDetail: "wall-detail",
  mainMode: "back-main", detailMode: "back-details", dim: "dim",
  opacity: "opacity", blur: "blur", acrylic: "acrylic",
  autoPopups: "auto-popups", uiScale: "ui-scale",
  lightMode: "light-mode", fontFamily: "font-family", fontSize: "font-size"
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
// Progress colors deliberately do NOT follow the selected theme.
// The filled length reveals the fixed spectrum at its real position in 0–100%.
export const PROGRESS_PALETTE = ["#243985","#3664ce","#477af4","#8155df","#b461ef"] as const;
export const PROGRESS_GRADIENT =
  "linear-gradient(90deg,#243985 0%,#3664ce 27%,#477af4 52%,#8155df 77%,#b461ef 100%)";
export function progressGradient(){return PROGRESS_GRADIENT}
export function progressColor(fraction: number) {
  const f=Math.max(0,Math.min(1,fraction))*4;
  const a=Math.min(3,Math.floor(f)),b=Math.min(4,a+1),w=f-a;
  const parse=(hex:string)=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16));
  const aa=parse(PROGRESS_PALETTE[a]),bb=parse(PROGRESS_PALETTE[b]);
  return "rgb("+aa.map((v,i)=>Math.round(v+(bb[i]-v)*w)).join(",")+")";
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
// One continuous, factual total-file percentage. Its gradient stays in the
// same absolute position as the file fills—purple is only reached near 100%.
export function GradientBar({percent,showLabel=false}:{percent:number;showLabel?:boolean}){
  const fill=Math.max(0,Math.min(100,percent));
  return <div className="cg-percent-wrap" aria-label={`Download ${fill.toFixed(1)} percent completed`}>
    <div className="cg-percent-track">
      {fill>0&&<span className="cg-percent-fill" style={{
        width:`${fill}%`,
        backgroundImage:PROGRESS_GRADIENT,
        backgroundSize:`${10000/fill}% 100%`
      }}/>}
    </div>{showLabel&&<strong>{fill.toFixed(0)}%</strong>}
  </div>;
}

// Engine segment ranges, NOT an animation of the overall percent.
// Each small block covers a real byte interval; its fill is the overlap
// with the engine's actual [segment.start, segment.cursor] downloaded ranges.
export function ChunkMap({segments,size,compact=false}:{
  segments:Segment[]|undefined;size:number|null;compact?:boolean
}){
  const range= Math.max(0,size??0,...(segments??[]).map(s=>s.end));
  const valid=(segments??[]).filter(s=>s.end>s.start&&s.cursor>=s.start);
  if(!valid.length||!Number.isFinite(range)||range<=0)
    return <div className={`cg-chunk-unavailable ${compact?"compact":""}`} title="MDM engine reports no segment ranges for this download">
      Segment data unavailable
    </div>;
  const blocks=compact?20:144, columns=compact?20:24;
  return <div className={`cg-chunk-map ${compact?"compact":""}`}
    style={{gridTemplateColumns:`repeat(${columns},minmax(0,1fr))`}}
    aria-label={`Actual segment byte map, ${valid.length} engine segments`}>
    {Array.from({length:blocks},(_,i)=>{
      const lo=range*i/blocks,hi=range*(i+1)/blocks;
      let received=0,active=false;
      for(const seg of valid){
        if(seg.end>lo&&seg.start<hi){
          active=true;
          received+=Math.max(0,Math.min(hi,seg.cursor)-Math.max(lo,seg.start));
        }
      }
      const filled=Math.max(0,Math.min(100,100*received/(hi-lo)));
      return <span key={i} title={`Byte range ${Math.floor(lo).toLocaleString()}–${Math.floor(hi).toLocaleString()}: ${filled.toFixed(0)}% received`}
        className={active?"active":""}>
        {filled>0&&<i style={{width:`${filled}%`,background:progressColor(i/Math.max(1,blocks-1))}}/>}
      </span>;
    })}
  </div>;
}

// Live connection/speed data only—one unique SVG gradient ID per graph, so
// many small row graphs never collide with each other or the footer graph.
export function SpeedGraph({values,small=false}:{values:number[];small?:boolean}){
  const id=useId().replace(/:/g,"-");
  const seq=values.length>1?values:[0,0],peak=Math.max(1,...seq)*1.12;
  const points=seq.map((v,i)=>(i/(seq.length-1)*100).toFixed(2)+","+(58-v/peak*48).toFixed(2)).join(" ");
  const trail=`0,65 ${points} 100,65`;
  return <svg className={`cg-graph ${small?"cg-graph-small":""}`} viewBox="0 0 100 65"
    preserveAspectRatio="none" role="img" aria-label="Real measured transfer-speed history">
    <defs>
      <linearGradient id={`${id}-line`} x1="0%" x2="100%" y1="0%" y2="0%">
        <stop offset="0%" stopColor="#315dbd"/><stop offset="45%" stopColor="#477af4"/>
        <stop offset="77%" stopColor="#8155df"/><stop offset="100%" stopColor="#b461ef"/>
      </linearGradient>
      <linearGradient id={`${id}-fill`} x1="0%" x2="100%" y1="0%" y2="0%">
        <stop offset="0%" stopColor="#315dbd" stopOpacity=".16"/>
        <stop offset="50%" stopColor="#477af4" stopOpacity=".23"/>
        <stop offset="100%" stopColor="#b461ef" stopOpacity=".25"/>
      </linearGradient>
    </defs>
    {[15,37,57].map(y=><line key={y} x1="0" x2="100" y1={y} y2={y}
      stroke="rgba(180,227,242,.11)" strokeWidth=".4"/>)}
    <polygon points={trail} fill={`url(#${id}-fill)`}/>
    <polyline points={points} fill="none" stroke={`url(#${id}-line)`} strokeWidth={small?"1.9":"1.7"}
      strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke"/>
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
    "--ui-scale": appearance.uiScale / 100,
    "--font-family": appearance.fontFamily === "Inter" ? "Inter, Segoe UI, sans-serif" : appearance.fontFamily === "Arial" ? "Arial, sans-serif" : appearance.fontFamily === "Consolas" ? "Consolas, monospace" : "Segoe UI Variable, Segoe UI, sans-serif",
    "--font-size": Math.min(20,Math.max(10,appearance.fontSize))+"px"
  } as CSSProperties;
  return <div className={`cg-window cg-mode-${mode} ${appearance.lightMode?"cg-light":"cg-dark"}`} style={style}>
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
