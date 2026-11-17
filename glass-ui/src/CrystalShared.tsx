import { invoke, convertFileSrc } from "@tauri-apps/api/core";
import { getCurrentWindow, Effect, EffectState } from "@tauri-apps/api/window";
type ResizeDirection = Parameters<ReturnType<typeof getCurrentWindow>["startResizeDragging"]>[0];
import { useEffect, useState, useLayoutEffect, useRef, useId, createContext, useContext } from "react";
import type { CSSProperties, ReactNode } from "react";
import { AppWindow, Maximize2, Minus, X, PanelBottomClose } from "lucide-react";

import { connectionGrid, connectionIndicators } from "./connections";

export type Status = "Queued" | "Downloading" | "Stopped" | "Complete" | "Error";
export type Download = {
  id: number; file: string; url: string; path: string; status: Status;
  size: number | null; downloaded: number; speed: number; added: string | null;
  category: string; error?: string | null
};
export type Queue = { name: string; running: boolean; ids: number[] };
export type Segment = { start: number; cursor: number; end: number; worker?:number|null; last_worker?:number|null };
export type Connection = { id: number; downloaded: number; speed: number; state: string };
export type ServerPlace={name:string|null;flag_cell:[number,number]|null;reach:string|null};
export function CountryFlag({place}:{place?:ServerPlace|null}){return place?.flag_cell?<span className="cg-country-flag" aria-label="Country flag" style={{backgroundPosition:`-${place.flag_cell[0]/2}px -${place.flag_cell[1]/2}px`}}/>:null;}
export type DownloadVisual = {
  id: number; chunk_count: number; active_connections:number; segments: Segment[]; connections: Connection[]; resumable: boolean | null;
  server: {hostname:string|null;ip:string|null;country_code:string|null;place?:ServerPlace|null;rtt_ms:number|null;cdn:string|null;proxied:boolean};
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
  { id: "navy", name: "Deep Indigo", accent: "#748cff", secondary: "#a679fd", rgb: "116,140,255" },
  { id: "orange", name: "Black Orange", accent: "#ff942f", secondary: "#ff5136", rgb: "255,148,47" },
  { id: "rose", name: "Rose Quartz", accent: "#ff82bb", secondary: "#b986ff", rgb: "255,130,187" }
];
export type BackgroundMode = "desktop" | "wallpaper" | "solid";
export type Appearance = {
  theme: string; wallMain: string; wallDetail: string; mainMode: BackgroundMode;
  detailMode: BackgroundMode; dim: number; opacity: number; blur: number;
  acrylic: boolean; autoPopups: boolean; uiScale: number; highContrast: boolean;
  lightMode: boolean; fontFamily: string; fontSize: number; material: string; indicator: string; progressShape: string; clipboardMode: string; tintHue: number; tintStrength: number
};
const key = "mh-glass-";
const stored = (name: string, fallback: string) => {
  try { return localStorage.getItem(key + name) ?? fallback }
  catch { return fallback }
};
export function loadAppearance(): Appearance {
  return {
    theme: stored("theme", "plexo"), material: ["ice-edge","smoked-crystal","frosted-layers","aero-gloss","prismatic-glass","liquid-glass","obsidian-glass","diamond-facet","holographic-film","pearl-mist","aurora-veil","brushed-glass","water-bubble"].includes(stored("material", "ice-edge")) ? stored("material", "ice-edge") : "ice-edge", tintHue: Number(stored("tint-hue", "265")), tintStrength: Number(stored("tint-strength", "22")), indicator: stored("indicator", "blue-purple"), progressShape: stored("progress-shape", "rounded"), clipboardMode: stored("clipboard-mode", "offer"),
    wallMain: stored("wall-main", ""), wallDetail: stored("wall-detail", ""),
    mainMode: stored("back-main", "desktop") as BackgroundMode,
    detailMode: stored("back-details", "desktop") as BackgroundMode,
    dim: Number(stored("dim", "26")), opacity: Number(stored("opacity", "77")),
    blur: Number(stored("blur", "3")), acrylic: stored("acrylic", "false") === "true",
    autoPopups: stored("auto-popups", "true") === "true", highContrast: stored("high-contrast", "true") === "true",
    uiScale: Number(stored("ui-scale", "100")),
    lightMode: stored("light-mode", "false") === "true",
    fontFamily: stored("font-family","Segoe UI"),fontSize:Number(stored("font-size","14"))
  };
}
const keys: Record<keyof Appearance, string> = {
  theme: "theme", material: "material", tintHue: "tint-hue", tintStrength: "tint-strength", indicator: "indicator", progressShape: "progress-shape", clipboardMode: "clipboard-mode", wallMain: "wall-main", wallDetail: "wall-detail",
  mainMode: "back-main", detailMode: "back-details", dim: "dim",
  opacity: "opacity", blur: "blur", acrylic: "acrylic",
  autoPopups: "auto-popups", uiScale: "ui-scale", highContrast: "high-contrast",
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
  useEffect(()=>{void invoke("window_preferences",{autoProgress:appearance.autoPopups}).catch(()=>undefined)},[appearance.autoPopups]);
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
export const indicatorPalettes: Record<string,{label:string; colors:[string,string,string]}> = {
  "blue-purple":{label:"Blue / Purple",colors:["#1778ff","#755cff","#d04eff"]},
  ocean:{label:"Ocean",colors:["#00aaff","#00d6d1","#4cf0a8"]},
  sunset:{label:"Sunset",colors:["#ffb52e","#ff6450","#f54eca"]},
  aurora:{label:"Aurora",colors:["#38efb5","#26baff","#c967ff"]},
  silver:{label:"Silver",colors:["#a0b3cc","#e4f2ff","#ffffff"]}
};
export function indicatorColors(id:string){return (indicatorPalettes[id]??indicatorPalettes["blue-purple"]).colors}
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
  const {appearance}=useCrystal();const colors=indicatorColors(appearance.indicator);
  const fill=Math.max(0,Math.min(100,percent));
  return <div className="cg-percent-wrap" aria-label={`Download ${fill.toFixed(1)} percent completed`}>
    <div className="cg-percent-track">
      {fill>0&&<span className="cg-percent-fill" style={{
        width:`${fill}%`,
        backgroundImage:`linear-gradient(90deg,${colors.join(",")})`,
        backgroundSize:`${10000/fill}% 100%`
      }}/>}
    </div>{showLabel&&<strong>{fill.toFixed(0)}%</strong>}
  </div>;
}

// Each block represents an engine worker and only its currently assigned ranges.
export function ConnectionMap({segments,connections,downloading,compact=false}:{segments:Segment[]|undefined;connections:Connection[]|undefined;downloading:boolean;compact?:boolean}){
  const {appearance}=useCrystal();const colors=indicatorColors(appearance.indicator);
  const items=connectionIndicators(connections??[],segments??[]);const grid=connectionGrid(items.length,compact);
  return <div className={"cg-chunks "+(compact?"compact":"")}>
    <div className="cg-chunk-label"><span>{connections?`${items.length} connections`:"Connections unavailable"}</span>{!compact&&<small>{items.filter(c=>downloading&&c.state==="Receiving").length} receiving</small>}</div>
    {items.length>0&&<div className={"cg-chunk-map "+(compact?"compact ":"")+((compact?grid.rows>=4:grid.rows>8)?"dense":"")} style={{gridTemplateColumns:`repeat(${grid.columns},minmax(0,1fr))`,gridTemplateRows:`repeat(${grid.rows},minmax(0,1fr))`,height:grid.height}} aria-label={`${items.length} engine connections`}>
     {items.map(c=>{const fill=c.percent;const label=`Connection ${c.id+1}: ${downloading?c.state:"Not active"}; downloaded ${units(c.downloaded)}; ${rate(c.speed)}; ${fill===null?"assigned range unavailable":`${units(c.received)} of ${units(c.assigned)} (${fill.toFixed(1)}%)`}`;
      return <span key={c.id} className={downloading&&c.state==="Receiving"?"active":""} title={label} aria-label={label} tabIndex={0}>{fill!==null&&fill>0&&<i style={{width:`${fill}%`,backgroundImage:`linear-gradient(90deg,${colors.join(",")})`}}/>}{!compact&&grid.rows<=2&&<em className="cg-connection-text">{c.id+1}{fill!==null?` · ${fill.toFixed(0)}%`:""}</em>}{downloading&&c.state==="Receiving"&&!compact&&<b className="cg-connection-active"/>}</span>})}
    </div>}
    {items.length===0&&!compact&&<small className="cg-muted">No connection data available</small>}
  </div>;
}

// Live connection/speed data only—one unique SVG gradient ID per graph, so
// many small row graphs never collide with each other or the footer graph.
export function SpeedGraph({values,small=false}:{values:number[];small?:boolean}){
  const {appearance}=useCrystal();const colors=indicatorColors(appearance.indicator);
  const id=useId().replace(/:/g,"-");
  const seq=values.length>1?values:[0,0],peak=Math.max(1,...seq)*1.12;
  const points=seq.map((v,i)=>(i/(seq.length-1)*100).toFixed(2)+","+(58-v/peak*48).toFixed(2)).join(" ");
  const trail=`0,65 ${points} 100,65`;
  return <svg className={`cg-graph ${small?"cg-graph-small":""}`} viewBox="0 0 100 65"
    preserveAspectRatio="none" role="img" aria-label="Real measured transfer-speed history">
    <defs>
      <linearGradient id={`${id}-line`} x1="0%" x2="100%" y1="0%" y2="0%">
        <stop offset="0%" stopColor={colors[0]}/><stop offset="50%" stopColor={colors[1]}/><stop offset="100%" stopColor={colors[2]}/>
      </linearGradient>
      <linearGradient id={`${id}-fill`} x1="0%" x2="100%" y1="0%" y2="0%">
        <stop offset="0%" stopColor={colors[0]} stopOpacity=".22"/>
        <stop offset="50%" stopColor={colors[1]} stopOpacity=".30"/>
        <stop offset="100%" stopColor={colors[2]} stopOpacity=".36"/>
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
    <button className="tray" title="Hide to tray" onClick={() => void w.hide()}><PanelBottomClose size={16}/></button>
    <button className="minimize" title="Minimize" onClick={() => void w.minimize()}><Minus size={17} /></button>
    {!noMax && <button className="maximize" title="Maximize or restore" onClick={() => void w.toggleMaximize()}><Maximize2 size={16} /></button>}
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
export function CrystalWindow({ children, target = "main", experimentalWater = false }: {
  children: ReactNode; target?: "main" | "details"; experimentalWater?: boolean
}) {
  const { appearance, theme } = useCrystal();
  const frame=useRef<HTMLDivElement>(null);
  const [fit,setFit]=useState(1),[windowError,setWindowError]=useState("");
  const [nativeWater,setNativeWater]=useState(0);
  const [waterPanelsReady,setWaterPanelsReady]=useState(false);
  const [waterPanelsRevision,setWaterPanelsRevision]=useState(0);
  useEffect(()=>{
    if(!experimentalWater)return;
    let active=true;
    void invoke<number>("experimental_water_surface",{rgb:parseInt(theme.accent.slice(1),16),light:appearance.lightMode,enabled:appearance.detailMode === "desktop",opacity:Math.round(appearance.opacity),tint:Math.round(appearance.tintStrength)})
      .then(enabled=>{if(active)setNativeWater(enabled)})
      .catch(()=>{if(active)setNativeWater(0)});
    return()=>{active=false};
  },[experimentalWater,theme.accent,appearance.lightMode,appearance.detailMode,appearance.opacity,appearance.tintStrength]);
  useEffect(()=>{
    const root=frame.current;
    if(nativeWater!==2||!root){setWaterPanelsReady(false);return;}
    let active=true,raf=0,last="";
    let queued:Promise<void>=Promise.resolve();
    const seen=new WeakSet<Element>();
    const nodes=()=>Array.from(root.querySelectorAll<HTMLElement>('.cg-minimal-progress > .cg-glass, .cg-indicator-row > .cg-glass')).slice(0,3);
    const observe=()=>{for(const node of nodes())if(!seen.has(node)){seen.add(node);observer.observe(node)}};
    const update=()=>{cancelAnimationFrame(raf);raf=requestAnimationFrame(()=>{
      if(!active)return;observe();const ratio=window.devicePixelRatio||1;
      const panels=nodes().map(node=>{const r=node.getBoundingClientRect();return [r.left*ratio,r.top*ratio,r.width*ratio,r.height*ratio].map(v=>Math.round(v*10)/10)}).filter(r=>r[2]>0&&r[3]>0);
      const key=JSON.stringify(panels);if(key===last)return;last=key;setWaterPanelsReady(false);
      queued=queued.then(()=>active?invoke<boolean>('experimental_water_panels',{panels}):false).then(ok=>{if(active&&last===key){setWaterPanelsReady(ok&&panels.length>0);if(ok)setWaterPanelsRevision(r=>r+1)}}).catch(()=>{if(active&&last===key){last="";setWaterPanelsReady(false)}});
    })};
    const observer=new ResizeObserver(update);observer.observe(root);observe();
    const mutations=new MutationObserver(update);mutations.observe(root,{childList:true,subtree:true});
    window.addEventListener('resize',update);update();
    return()=>{active=false;cancelAnimationFrame(raf);observer.disconnect();mutations.disconnect();window.removeEventListener('resize',update)};
  },[nativeWater]);
  useEffect(()=>{const report=(event:Event)=>setWindowError(String((event as CustomEvent).detail));window.addEventListener("glass-window-error",report);return()=>window.removeEventListener("glass-window-error",report)},[]);
  useLayoutEffect(()=>{
    const el=frame.current;if(!el)return;
    let disposed=false,raf=0;
    const baseScale=()=>appearance.uiScale/100;
    const measure=()=>{
      cancelAnimationFrame(raf);raf=requestAnimationFrame(()=>{
        if(disposed)return;
        const fit=el.querySelector<HTMLElement>('.cg-fit-content');if(!fit)return;
        let ratio=1;
        for(const box of [fit,...el.querySelectorAll<HTMLElement>('.cg-page,.cg-window-add,.cg-settings-body,.cg-settings-nav,.cg-main-body,.cg-workspace,.cg-toolbar,.cg-window-top,.cg-original-editor')]){
          if(box.clientHeight>0&&box.scrollHeight>box.clientHeight+2)ratio=Math.min(ratio,box.clientHeight/box.scrollHeight);
          if(box.clientWidth>0&&box.scrollWidth>box.clientWidth+2)ratio=Math.min(ratio,box.clientWidth/box.scrollWidth);
        }
        if(ratio<.998)setFit(old=>Math.max(target === "main" ? .85 : .7,old*ratio*.99));
      });
    };
    const reset=()=>{setFit(baseScale());measure()};
    const observer=new ResizeObserver(measure);observer.observe(el);
    const content=el.querySelector('.cg-fit-content');if(content)observer.observe(content);
    const mutations=new MutationObserver(measure);mutations.observe(el,{childList:true,subtree:true});
    const sectionClick=(event:Event)=>{if((event.target as Element).closest('nav button,.cg-appearance-tabs button,details summary'))reset()};
    el.addEventListener('click',sectionClick);el.addEventListener('change',reset);el.addEventListener('toggle',reset,true);
    window.addEventListener('resize',reset);reset();
    return()=>{disposed=true;cancelAnimationFrame(raf);observer.disconnect();mutations.disconnect();el.removeEventListener('click',sectionClick);el.removeEventListener('change',reset);el.removeEventListener('toggle',reset,true);window.removeEventListener('resize',reset)};
  },[appearance.uiScale,appearance.fontSize,appearance.fontFamily,target]);
  const main = target === "main", mode = main ? appearance.mainMode : appearance.detailMode;
  const path = main ? appearance.wallMain : (appearance.wallDetail || appearance.wallMain);
  const src = path ? convertFileSrc(path) : "/alpine.svg";
  const video = /\.(mp4|webm|mov|m4v)$/i.test(path);
  useEffect(() => {
    const w = getCurrentWindow();let active=true;
    if (mode === "desktop" && appearance.acrylic)
      void w.setEffects({ effects: [Effect.Acrylic], state: EffectState.Active }).catch(()=>{if(active)setWindowError("Windows backdrop blur is unavailable; transparent glass is being used.");return w.clearEffects().catch(()=>undefined)});
    else void w.clearEffects().catch(() => undefined);
    return()=>{active=false};
  }, [mode, appearance.acrylic]);
  const style = {
    "--accent": appearance.lightMode ? (({plexo:"#086e84",ocean:"#146c9b",purple:"#7050b5",pink:"#b73962",gold:"#8a5b05",green:"#19765b",silver:"#4c6680",navy:"#394ea2",orange:"#ad4700",rose:"#a42b70"} as Record<string,string>)[theme.id]??"#086e84") : theme.accent,
    "--accent-secondary": theme.secondary,
    "--accent-rgb": appearance.lightMode ? (({plexo:"8,110,132",ocean:"20,108,155",purple:"112,80,181",pink:"183,57,98",gold:"138,91,5",green:"25,118,91",silver:"76,102,128",navy:"57,78,162",orange:"173,71,0",rose:"164,43,112"} as Record<string,string>)[theme.id]??"8,110,132") : theme.rgb,
    "--surface-accent": Math.max(0,Math.min(65,appearance.tintStrength))/100,
    "--panel-opacity": Math.min(.94, Math.max(.45, appearance.opacity / 100)),
    "--crystal-blur": appearance.blur + "px",
    "--ui-scale": 1,
    "--fit-scale": Math.max(.7,fit),
    "--font-family": ({"Segoe UI":"Segoe UI Variable, Segoe UI, sans-serif", "Inter":"Inter, Segoe UI, sans-serif", "Arial":"Arial, sans-serif", "Consolas":"Consolas, monospace", "Trebuchet MS":"Trebuchet MS, sans-serif", "Verdana":"Verdana, sans-serif", "Georgia":"Georgia, serif", "Candara":"Candara, sans-serif", "Century Gothic":"Century Gothic, sans-serif", "Palatino Linotype":"Palatino Linotype, serif", "Tahoma":"Tahoma, sans-serif"} as Record<string,string>)[appearance.fontFamily] ?? "Segoe UI Variable, Segoe UI, sans-serif",
    "--min-text-size": (12/Math.max(.4,fit))+"px",
    "--min-icon-size": (16/Math.min(1,Math.max(.4,fit)))+"px",
    "--min-window-button": (30/Math.min(1,Math.max(.4,fit)))+"px",
    "--font-size": Math.max(Math.min(20,Math.max(12,appearance.fontSize)),12/Math.max(.4,fit))+"px"
  } as CSSProperties;
  return <div className={`cg-window ${nativeWater?"cg-native-water-experiment":""} cg-mode-${mode} cg-progress-shape-${appearance.progressShape} ${appearance.lightMode?"cg-light":"cg-dark"} ${appearance.highContrast?"cg-high-contrast":""}`} data-native-water-backdrop={nativeWater===2?"host":nativeWater===1?"opaque":"off"} data-native-water-panels={waterPanelsReady?"ready":"fallback"} data-native-water-revision={waterPanelsRevision} style={style}>
    {mode === "wallpaper" && <div className="cg-wallpaper">
      {video ? <video key={src} autoPlay loop muted playsInline src={src} /> :
        <div style={{ backgroundImage: `url("${src}")` }} />}
      <span style={{ background: `rgba(3,9,19,${appearance.dim / 100})` }} />
    </div>}
    {mode === "solid" && <div className="cg-solid" />}
    <div className="cg-content" ref={frame}><div className="cg-fit-content">{children}</div></div>
    {windowError&&<aside className="cg-window-notice cg-error" role="alert"><span>{windowError}</span><button title="Dismiss" onClick={()=>setWindowError("")}><X size={15}/></button></aside>}
    <ResizeGrips />
  </div>;
}
export function openWindow(label: string, url: string, width: number, height: number) {
  void invoke("open_glass_window",{label,url,width,height}).catch(e=>{
    window.dispatchEvent(new CustomEvent("glass-window-error",{detail:String(e)}));
  });
}
