import {isTiledWindow} from "./windowTiling";
import {nativeBackdrop} from "./nativeBackdrop";
import {LiquidProgress, LiquidChunk, InletDroplet, isLiquidMaterial} from "./LiquidIndicators";
import {ConnectionTubes} from "./ConnectionTubes";
import {receivingTubeSlots} from "./tubeNetwork";
import {loadMaterials,materialId,extraMaterials,materialBackdrop,resolveMaterial} from "./customMaterials";
import {loadThemes,paletteForTheme} from "./themeFiles";
import FrostedRibbon from "./FrostedRibbon";
import {BubbleProgress} from "./BubbleProgress";
import FrostedLayers from "./FrostedLayers";
import { invoke, convertFileSrc } from "@tauri-apps/api/core";
import { getCurrentWindow, currentMonitor, Effect, EffectState } from "@tauri-apps/api/window";
type ResizeDirection = Parameters<ReturnType<typeof getCurrentWindow>["startResizeDragging"]>[0];
import { useEffect, useState, useLayoutEffect, useRef, useId, useMemo, createContext, useContext } from "react";
import type { CSSProperties, ReactNode } from "react";
import { Maximize2, Minus, X, PanelBottomClose } from "lucide-react";

import { connectionIndicators, connectionSlots, connectionLost } from "./connections";

export type Status = "Queued" | "Downloading" | "Stopped" | "Complete" | "Error";
export type Download = {
  id: number; file: string; url: string; path: string; status: Status;
  size: number | null; downloaded: number; speed: number; added: string | null;
  category: string; error?: string | null
};
export type Queue = { name: string; running: boolean; ids: number[] };
export type Segment = { start: number; cursor: number; end: number; worker?:number|null; last_worker?:number|null };
export type Connection = { id: number; downloaded: number; speed: number; state: string; recent_disconnect?:boolean; reconnecting_after_loss?:boolean };
export type ServerPlace={name:string|null;flag_cell:[number,number]|null;reach:string|null};
export function CountryFlag({place}:{place?:ServerPlace|null}){return place?.flag_cell?<span className="cg-country-flag" aria-label="Country flag" style={{backgroundPosition:`-${place.flag_cell[0]/2}px -${place.flag_cell[1]/2}px`}}/>:null;}
export type DownloadVisual = {
  id: number; chunk_count: number; active_connections:number; segments: Segment[]; connections: Connection[]; resumable: boolean | null;
  server: {hostname:string|null;ip:string|null;country_code:string|null;place?:ServerPlace|null;rtt_ms:number|null;cdn:string|null;proxied:boolean};
  last_try:string|null;added:string|null;referer:string|null;page:string|null;
  description:string;category:string;is_torrent:boolean;direct_recovery?:boolean;original_partial?:string|null;recovery_search_available?:boolean;recovery_auto_search?:boolean;recovery_handoff_available?:boolean;is_video?:boolean;is_gallery?:boolean;is_remote?:boolean;recovery_damaged?:boolean
};
export type VisualDashboard = {downloads:DownloadVisual[]};

export type Dashboard = {
  downloads: Download[]; speed: number; queues: Queue[];
  categories: { name: string; key: string }[]; free?: number | null
};
export type Theme = { id: string; name: string; accent: string; secondary: string; rgb: string; neutralTint?: [number,number,number]; light?: boolean };
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
  { id: "rose", name: "Rose Quartz", accent: "#ff82bb", secondary: "#b986ff", rgb: "255,130,187" },
  { id:"glacier-ice",name:"Glacier Blue Ice",accent:"#57d5ff",secondary:"#287cff",rgb:"87,213,255" },
  { id:"amethyst-ice",name:"Amethyst Ice",accent:"#d091ff",secondary:"#7544f4",rgb:"208,145,255" },
  { id:"emerald-frost",name:"Emerald Frost",accent:"#50edc4",secondary:"#05a676",rgb:"80,237,196" },
  { id:"rose-crystal",name:"Rose Quartz Ice",accent:"#ff8bc6",secondary:"#d74c9c",rgb:"255,139,198" },
  { id:"amber-crystal",name:"Amber Crystal",accent:"#ffc15d",secondary:"#ef8421",rgb:"255,193,93" },
  { id:"obsidian-aurora",name:"Obsidian Aurora",accent:"#58e8dd",secondary:"#a36bff",rgb:"88,232,221" },
  { id:"black-onyx",name:"Black Onyx",accent:"#c5d4e0",secondary:"#4c5660",rgb:"197,212,224",neutralTint:[8,10,14] },
  { id:"black-smoke",name:"Smoke Black",accent:"#d0d9e0",secondary:"#727e88",rgb:"208,217,224",neutralTint:[48,52,58] },
  { id:"white-frost",name:"Frost White",accent:"#e8f4ff",secondary:"#b7c6d4",rgb:"232,244,255",neutralTint:[245,250,255] },
  { id:"white-pearl",name:"Pearl White",accent:"#fff3df",secondary:"#d8d0c5",rgb:"255,243,223",neutralTint:[245,239,230] }
];
function mixColor(a:number[],b:number[],amount:number){return a.map((v,i)=>Math.round(v*(1-amount)+b[i]*amount)).join(",")}
function secondaryRgb(theme:Theme){return [1,3,5].map(i=>parseInt(theme.secondary.slice(i,i+2),16))}
export function themeHue(theme:Theme){
 const [r,g,b]=theme.rgb.split(',').map(v=>Number(v)/255),max=Math.max(r,g,b),min=Math.min(r,g,b),delta=max-min;
 if(!delta)return 0;const hue=max===r?((g-b)/delta)%6:max===g?(b-r)/delta+2:(r-g)/delta+4;
 return Math.round((hue*60+360)%360);
}
export type BackgroundMode = "desktop" | "wallpaper" | "solid";
const validSolidColor = (color: string) => /^#[0-9a-f]{6}$/i.test(color);
const materialColors: Record<string, {dark: number[]; light: number[]}> = {
  "brushed-glass": {dark: [13,39,45], light: [207,230,229]},
  "frosted-water-351": {dark: [16,49,75], light: [209,238,254]},
  "rose-pine": {dark: [46,25,41], light: [248,226,225]},
  "oversimplified": {dark: [17,19,43], light: [232,231,248]},
  "builtin-obsidian-matte": {dark: [28,23,20], light: [238,225,208]},
  "builtin-smoked-glass": {dark: [40,32,29], light: [231,216,195]},
  "builtin-black-glass": {dark: [8,10,14], light: [8,10,14]},
  "builtin-pearl-frost": {dark: [47,38,64], light: [248,241,239]},
  "builtin-aurora-night": {dark: [8,16,47], light: [8,16,47]},
  "builtin-aurora-ice": {dark: [210,239,255], light: [210,239,255]},
};

function usesLightSurface(material: string, theme: Theme): boolean {
  if (material === "builtin-aurora-ice") return true;
  if (material === "builtin-aurora-night" || material === "builtin-black-glass") return false;
  return theme.light === true || theme.id === "white-frost" || theme.id === "white-pearl";
}

function materialSurfaceColor(material: string, theme: Theme, light: boolean): number[] {
  const preset = materialColors[material];
  if (preset) return light ? preset.light : preset.dark;
  const tint = theme.neutralTint ?? theme.rgb.split(",").map(Number);
  const shade = light ? 1 : theme.neutralTint ? .65 : .20;
  return tint.map(channel => Math.round(channel * shade));
}

export function defaultSolidColor(material: string, theme: Theme): string {
  const channels = materialSurfaceColor(material, theme, usesLightSurface(material, theme));
  return "#" + channels.map(channel => channel.toString(16).padStart(2,"0")).join("");
}
export type Appearance = {
  theme: string; wallMain: string; wallDetail: string; mainMode: BackgroundMode;
  detailMode: BackgroundMode; mainSolidColor: string; detailSolidColor: string; dim: number; opacity: number; blur: number; glassTranslucency: number | null;
  acrylic: boolean; autoPopups: boolean; uiScale: number; highContrast: boolean;
  lightMode: boolean; fontFamily: string; fontSize: number; material: string; surfaceStyle: string; indicator: string; progressMaterial: string; connectionMaterial: string; graphMaterial: string; trackFinish: string; trackColor: string; progressShape: string; graphIndicator: string; graphShape: string; connectionTrackFinish: string; connectionTrackColor: string; connectionIndicator: string; connectionShape: string; clipboardMode: string; tintHue: number; tintStrength: number
};
const key = "mh-glass-";
const stored = (name: string, fallback: string) => {
  try { return localStorage.getItem(key + name) ?? fallback }
  catch { return fallback }
};
// Record which defaults an installation started with. Existing profiles keep
// their prior missing-value defaults; new profiles can adopt the new style.
function appearanceDefaults(){
 try {
  const marker="auralis-appearance-defaults-version";
  let version=localStorage.getItem(marker);
  if(version!=="1"&&version!=="2"){
   const existing=Object.keys(localStorage).some(k=>k.startsWith(key))||localStorage.getItem("auralis-browser-guide-seen")!==null;
   version=existing?"1":"2";localStorage.setItem(marker,version);
  }
  return version==="1";
 } catch { return false }
}
const supportedShape=(shape:string)=>["wave","droplet"].includes(shape)?"bubble":["rounded","square","faceted","bubble"].includes(shape)?shape:"rounded";
const supportedFill=(value:string)=>value==="gradient"?"gradient":"liquid-glass";
const supportedPalette=(value:string)=>value==="neon"?"blue-purple":value;
export function loadAppearance(): Appearance {
  const legacy=appearanceDefaults();
  const translucency = Number(stored("glass-translucency", "auto"));
  const mainSolid = stored("solid-main", ""), detailSolid = stored("solid-details", "");
  return {
    glassTranslucency: Number.isInteger(translucency) && translucency >= 0 && translucency <= 100 ? translucency : null,
    theme: stored("theme", legacy?"silver":"ocean"), material: [...["brushed-glass","frosted-water-351","rose-pine","oversimplified"],...Object.keys(extraMaterials),...loadMaterials().map(materialId)].includes(stored("material", legacy?"frosted-water-351":"rose-pine")) ? stored("material", legacy?"frosted-water-351":"rose-pine") : (legacy?"frosted-water-351":"rose-pine"), tintHue: Number(stored("tint-hue", legacy?"209":"203")), tintStrength: Number(stored("tint-strength", legacy?"50":"0")), indicator: supportedPalette(stored("indicator", legacy?"blue-purple":"aurora")), progressMaterial: supportedFill(stored("progress-material", legacy?"gradient":"liquid-glass")), connectionMaterial: supportedFill(stored("connection-material", legacy?"gradient":"liquid-glass")), graphMaterial: supportedFill(stored("graph-material", "gradient")), trackFinish: stored("track-finish", "recessed"), trackColor: stored("track-color", "ice"), progressShape: supportedShape(stored("progress-shape", "rounded")), graphIndicator: supportedPalette(stored("graph-indicator", stored("indicator", legacy?"blue-purple":"aurora"))), graphShape: stored("graph-shape", "area"), connectionTrackFinish: stored("connection-track-finish", "recessed"), connectionTrackColor: stored("connection-track-color", "ice"), connectionIndicator: supportedPalette(stored("connection-indicator", stored("indicator", legacy?"blue-purple":"aurora"))), connectionShape: supportedShape(stored("connection-shape", stored("progress-shape", "rounded"))), clipboardMode: stored("clipboard-mode", "paste"),
    surfaceStyle: ["material","clear","soft","frosted","tinted"].includes(stored("surface-style","material")) ? stored("surface-style","material") : "material",
    wallMain: stored("wall-main", ""), wallDetail: stored("wall-detail", ""),
    mainSolidColor: validSolidColor(mainSolid) ? mainSolid : "",
    detailSolidColor: validSolidColor(detailSolid) ? detailSolid : "",
    mainMode: stored("back-main", "desktop") as BackgroundMode,
    detailMode: stored("back-details", "desktop") as BackgroundMode,
    dim: Number(stored("dim", "26")), opacity: Number(stored("opacity", "100")),
    blur: Number(stored("blur", legacy?"3":"6")), acrylic: stored("acrylic", "false") === "true",
    autoPopups: stored("auto-popups", "true") === "true", highContrast: stored("high-contrast", "true") === "true",
    uiScale: Number(stored("ui-scale", legacy?"90":"97")),
    lightMode: stored("light-mode", "false") === "true",
    fontFamily: stored("font-family","Trebuchet MS"),fontSize:Number(stored("font-size","14"))
  };
}
const keys: Record<keyof Appearance, string> = {
  theme: "theme", material: "material", tintHue: "tint-hue", tintStrength: "tint-strength", indicator: "indicator", progressMaterial: "progress-material", connectionMaterial: "connection-material", graphMaterial: "graph-material", trackFinish: "track-finish", trackColor: "track-color", progressShape: "progress-shape", graphIndicator: "graph-indicator", graphShape: "graph-shape", connectionTrackFinish: "connection-track-finish", connectionTrackColor: "connection-track-color", connectionIndicator: "connection-indicator", connectionShape: "connection-shape", clipboardMode: "clipboard-mode", wallMain: "wall-main", wallDetail: "wall-detail",
  mainMode: "back-main", detailMode: "back-details", mainSolidColor: "solid-main", detailSolidColor: "solid-details", dim: "dim",
  opacity: "opacity", blur: "blur", glassTranslucency: "glass-translucency", acrylic: "acrylic", surfaceStyle: "surface-style",
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
    if (value === null) localStorage.removeItem(key + keys[name]);
    else localStorage.setItem(key + keys[name], String(value));
    setAppearance(prev => ({ ...prev, [name]: value }));
  };
  const theme = themes.find(t => t.id === appearance.theme) ?? loadThemes().map(t=>paletteForTheme(t.palette)).find(t=>t.id===appearance.theme) ?? themes[0];
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
  silver:{label:"Silver",colors:["#a0b3cc","#e4f2ff","#ffffff"]},
  cobalt:{label:"Solid cobalt",colors:["#347dff","#347dff","#347dff"]},
  emerald:{label:"Solid emerald",colors:["#14cf8c","#14cf8c","#14cf8c"]},
  tangerine:{label:"Solid orange",colors:["#ff8c21","#ff8c21","#ff8c21"]},
  coral:{label:"Solid coral",colors:["#ff566c","#ff566c","#ff566c"]},
  violet:{label:"Solid violet",colors:["#ad6bff","#ad6bff","#ad6bff"]},
  lime:{label:"Solid lime",colors:["#b9ed34","#b9ed34","#b9ed34"]},
  candy:{label:"Candy",colors:["#ff63a8","#ffa35b","#ffe36c"]},
  arctic:{label:"Arctic",colors:["#a4ffff","#84bdff","#e8ddff"]},
  fire:{label:"Fire",colors:["#ffdd32","#ff7b20","#fa3652"]},
  forest:{label:"Forest",colors:["#b7ef45","#28d897","#007f85"]},
  neon:{label:"Neon",colors:["#ff3ca5","#c351ff","#57e9ff"]}
};
export function indicatorColors(id:string){return (indicatorPalettes[id]??indicatorPalettes["blue-purple"]).colors}
function backdropPalette(id:string){return id.startsWith("palette:") ? indicatorPalettes[id.slice(8)]?.colors : undefined}
function backdropStyle(id:string):CSSProperties {const colors=backdropPalette(id);return colors?({"--cg-backdrop-a":colors[0],"--cg-backdrop-b":colors[1],"--cg-backdrop-c":colors[2]} as CSSProperties):{}}
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
export function GradientBar({percent,showLabel=false,size,active=true}:{percent:number;showLabel?:boolean;size?:number|null;active?:boolean}){
  const {appearance}=useCrystal();const colors=indicatorColors(appearance.indicator);
  const fill=Math.max(0,Math.min(100,percent));
  const bubble = appearance.progressShape === "bubble";
  const backdrop = backdropPalette(appearance.trackColor);
  const trackClass = bubble ? "cg-bubble-track" : `cg-track-${appearance.trackFinish} cg-track-color-${appearance.trackColor}${backdrop ? " cg-palette-track" : ""}`;
  return <div className="cg-percent-wrap" aria-label={`Download ${fill.toFixed(1)} percent completed`}>
    <div className={`cg-percent-track ${trackClass}`} style={{...(!bubble && backdropStyle(appearance.trackColor)),"--indicator-glow":colors[1]} as CSSProperties}>
      {bubble ? <BubbleProgress percent={fill} colors={colors} backdrop={backdrop} finish={appearance.trackFinish} tint={appearance.trackColor} material={appearance.progressMaterial} size={size} active={active}/> : isLiquidMaterial(appearance.progressMaterial) ? <LiquidProgress percent={fill} colors={colors} material={appearance.progressMaterial} size={size} active={active}/> : appearance.progressMaterial === "frosted-ribbon" ? <FrostedRibbon shape={appearance.progressShape} percent={fill} colors={colors} finish={appearance.trackFinish} tint={appearance.trackColor} tintColors={backdropPalette(appearance.trackColor)} fallback={`linear-gradient(90deg,${colors.join(",")})`}/> : fill>0&&<span className="cg-percent-fill" style={{
        width:`${fill}%`,
        backgroundImage:`linear-gradient(90deg,${colors.join(",")})`,
        backgroundSize:`${10000/fill}% 100%`,
        boxShadow:`inset 0 2px 4px #ffffffa0, inset 0 -3px 6px #03122b99, 0 0 10px ${colors[1]}99`
      }}/>}
    </div>{showLabel&&<strong>{fill.toFixed(0)}%</strong>}
  </div>;
}

// Each block represents an engine worker and only its currently assigned ranges.
export function ConnectionMap({segments,connections,downloading,paused=false,compact=false,tubes=false}:{segments:Segment[]|undefined;connections:Connection[]|undefined;downloading:boolean;paused?:boolean;compact?:boolean;tubes?:boolean}){
  const {appearance}=useCrystal();const colors=indicatorColors(appearance.connectionIndicator);
  const gridRef=useRef<HTMLDivElement>(null);
  const raw=connectionIndicators(connections??[],segments??[]);
  const last=useRef<typeof raw>([]);
  const items=raw.map(c=>{const old=last.current.find(x=>x.id===c.id);return connectionLost(c,downloading)&&c.percent===null&&old?.percent!=null?{...c,assigned:old.assigned,received:old.received,percent:old.percent}:c});
  if(downloading&&items.length>0)last.current=items;
  const visible=paused&&items.length===0?last.current:items;
  const shown=compact?visible:visible.slice(0,32);
  const slots=connectionSlots(shown,compact);
  const liquid=isLiquidMaterial(appearance.connectionMaterial);
  const gridStyle={
    ...backdropStyle(appearance.connectionTrackColor),
    "--indicator-glow":colors[1],
    "--indicator-rim":colors[2],
    ...(compact?{gridTemplateColumns:`repeat(${Math.max(1,slots.length)},minmax(0,1fr))`}:{}),
  } as CSSProperties;
  return <div className={"cg-chunks "+(compact?"compact":"")}>
    {compact&&<div className="cg-chunk-label"><span>{connections?`${visible.length} connections`:"Connections unavailable"}</span></div>}
    <div ref={gridRef} className={`cg-chunk-map cg-connection-track-${appearance.connectionTrackFinish} cg-connection-tint-${appearance.connectionTrackColor} ${backdropPalette(appearance.connectionTrackColor)?"cg-palette-track":""} `+(compact?"compact":"cg-fixed-connections")+(tubes&&!compact?" cg-piped-connections":"")} style={gridStyle} role="group" aria-label={connections?`${visible.length} engine connections${visible.length>32?', first 32 shown':''}`:"Connections unavailable"}>
      {tubes&&!compact&&<ConnectionTubes container={gridRef} slots={receivingTubeSlots(connections,downloading&&!paused)} colors={indicatorColors(appearance.indicator)}/>}
      {slots.map((connection,index)=>{
        if(!connection)return <span key={`empty-${index}`} className="cg-connection-empty" aria-hidden="true"/>;
        const {id,percent:fill,state,downloaded,speed,received,assigned}=connection;
        const active=!paused&&downloading&&state==="Receiving";
        const lost=connectionLost(connection,downloading);
        const status=paused?"Paused":lost?"Connection lost or retrying":downloading?state:"Not active";
        const range=fill===null?"assigned range unavailable":`${units(received)} of ${units(assigned)} (${fill.toFixed(1)}%)`;
        const label=`Connection ${id+1}: ${status}; downloaded ${units(downloaded)}; ${rate(speed)}; ${range}. Assigned sections can change as work is redistributed.`;
        const hasFill=!paused&&fill!==null&&(fill>0||(active&&!lost&&liquid));
        return <span key={id} data-worker={id} className={paused?"paused":lost?"lost":active?"active":""} title={label} aria-label={label} tabIndex={0}>
          {hasFill&&<span className="cg-connection-fill cg-indicator-bloom" aria-hidden="true">
            {liquid
              ?<LiquidChunk percent={fill} colors={colors} material={appearance.connectionMaterial} animate={active&&!lost} index={id}/>
              :<i className="cg-connection-default-fill" style={{height:`${fill}%`,backgroundImage:`linear-gradient(180deg,#ffffff65,transparent 38%,#06133244),linear-gradient(0deg,${colors.join(",")})`}}/>}
          </span>}
          {active&&!lost&&<InletDroplet percent={fill??0} colors={colors} index={id}/>}
        </span>;
      })}
    </div>
  </div>;
}

const clampGraph=(value:number)=>Math.max(0,Math.min(1,Number.isFinite(value)?value:0));
// Live connection/speed data only—one unique SVG gradient ID per graph, so
// many small row graphs never collide with each other or the footer graph.
export function SpeedGraph({values,small=false}:{values:number[];small?:boolean}){
  const {appearance}=useCrystal();const colors=indicatorColors(appearance.graphIndicator);
  const id=useId().replace(/:/g,"-");
  const seq=values.length>1?values:[0,0],peak=Math.max(1,...seq)*1.12;
  const liquid=isLiquidMaterial(appearance.graphMaterial);
  const coords=seq.map((v,i)=>({x:i/(seq.length-1)*100,y:(liquid?65:58)-clampGraph(v/peak)*(liquid?55:48)}));
  const points=coords.map(({x,y})=>`${x},${y}`).join(" ");
  const trail=`0,65 ${points} 100,65`;
  const curved=coords.slice(1).reduce((path,pt,i)=>{const prev=coords[i],mid=(prev.x+pt.x)/2;return `${path} C${mid},${prev.y} ${mid},${pt.y} ${pt.x},${pt.y}`},`M${coords[0].x},${coords[0].y}`);
  const surface=`${curved} L100,65 L0,65 Z`;
  return <svg className={`cg-graph ${small?"cg-graph-small":""} ${liquid?`cg-liquid-graph ${appearance.graphMaterial}`:""}`} viewBox="0 0 100 65"
    preserveAspectRatio="none" style={{"--indicator-glow":colors[1],"--indicator-rim":colors[2]} as CSSProperties} role="img" aria-label="Real measured transfer-speed history">
    <defs>
      <linearGradient id={`${id}-line`} x1="0%" x2="100%" y1="0%" y2="0%">
        <stop offset="0%" stopColor={colors[0]}/><stop offset="50%" stopColor={colors[1]}/><stop offset="100%" stopColor={colors[2]}/>
      </linearGradient>
      <linearGradient id={`${id}-fill`} x1="0%" x2="100%" y1="0%" y2="0%">
        <stop offset="0%" stopColor={colors[0]} stopOpacity=".22"/>
        <stop offset="50%" stopColor={colors[1]} stopOpacity=".30"/>
        <stop offset="100%" stopColor={colors[2]} stopOpacity=".36"/>
      </linearGradient>
      <clipPath id={`${id}-liquid-clip`}><path d={surface}/></clipPath>
      <linearGradient id={`${id}-depth`} x1="0" x2="0" y1="0" y2="1"><stop stopColor="#fff" stopOpacity={appearance.graphMaterial==='liquid-crystal'?'.65':appearance.graphMaterial==='liquid-aero'?'.32':'.45'}/><stop offset=".3" stopColor="#fff" stopOpacity=".02"/><stop offset="1" stopColor="#00102e" stopOpacity={appearance.graphMaterial==='liquid-crystal'?'.72':'.50'}/></linearGradient>
    </defs>

    {[15,37,57].map(y=><line key={y} x1="0" x2="100" y1={y} y2={y}
      stroke="rgba(180,227,242,.11)" strokeWidth=".4"/>)}
    <g className="cg-graph-data cg-indicator-bloom">
    {appearance.graphShape==="area"&&(liquid?<><path d={surface} fill={`url(#${id}-line)`} opacity=".72"/><path d={surface} fill={`url(#${id}-depth)`}/><g clipPath={`url(#${id}-liquid-clip)`}><g className="cg-liquid-graph-light"><path d="M-25 33 Q0 20 25 33 T75 33 T125 33" fill="none" stroke="rgba(220,255,255,.14)" strokeWidth="1.2" vectorEffect="non-scaling-stroke"/></g>{appearance.graphMaterial==='liquid-glass'&&[14,36,61,83].map((x,i)=><circle key={x} cx={x} cy={54+(i%2)*5} r=".65" fill="none" stroke="rgba(235,255,255,.4)" strokeWidth=".3"/>)}{appearance.graphMaterial==='liquid-crystal'&&<path d={curved} transform="translate(0 3)" fill="none" stroke="rgba(240,255,255,.32)" strokeWidth=".6" vectorEffect="non-scaling-stroke"/>}{appearance.graphMaterial==='liquid-aero'&&<path d={curved} transform="translate(0 5)" fill="none" stroke="rgba(240,255,255,.18)" strokeWidth="3" vectorEffect="non-scaling-stroke"/>}</g></>:<polygon points={trail} fill={`url(#${id}-fill)`}/>)}
    {appearance.graphShape==="bars"&&seq.map((v,i)=>{const ratio=clampGraph(v/peak),x=i*100/seq.length,width=Math.max(.1,80/seq.length),y=(liquid?65:58)-ratio*(liquid?55:48),height=ratio*(liquid?55:48);return <g key={i}><rect x={x} y={y} width={width} height={height} fill={`url(#${id}-line)`}/>{liquid&&<rect x={x} y={y} width={width} height={height} fill={`url(#${id}-depth)`}/>}</g>})}
    {appearance.graphShape!=="bars"&&(liquid?<path d={curved} fill="none" stroke={`url(#${id}-line)`} strokeWidth={small?"2.4":"2.1"} strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke"/>:<polyline points={points} fill="none" stroke={`url(#${id}-line)`} strokeWidth={small?"1.9":"1.7"} strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke"/>)}
    {appearance.graphShape!=="bars"&&(liquid
      ?<path d={curved} fill="none" stroke="rgba(240,255,255,.68)" strokeWidth=".65" strokeLinecap="round" vectorEffect="non-scaling-stroke"/>
      :<polyline points={points} fill="none" stroke="rgba(240,255,255,.63)" strokeWidth=".65" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke"/>)}
    </g>
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
    <button className="tray" title="Hide to tray" onClick={() => { const id=Number(new URLSearchParams(location.search).get("detail"))||0; if(id) void invoke("hide_download_to_tray",{id}).catch(()=>undefined); else void w.hide(); }}><PanelBottomClose size={16}/></button>
    <button className="minimize" title="Minimize" onClick={() => void w.minimize()}><Minus size={17} /></button>
    {!noMax && <button className="maximize" title="Maximize or restore" onClick={() => void w.toggleMaximize()}><Maximize2 size={16} /></button>}
    <button className="close" title="Close" onClick={() => void w.close()}><X size={20} /></button>
  </div>;
}
export function WindowTop({ title, children, noMax = false }: {
  title: string; children?: ReactNode; noMax?: boolean
}) {
  return <header className="cg-window-top">
    <div className="cg-title"
      onMouseDown={e => { if (e.button !== 0) return; if (e.detail === 2 && !noMax) { e.preventDefault(); void getCurrentWindow().toggleMaximize(); } else if (e.detail === 1) void getCurrentWindow().startDragging(); }}>
      <span className="cg-logo"><img src="/auralis.svg" alt="" width="22" height="22" draggable="false" /></span>
      <span>{title}</span>
    </div>{children}<WindowButtons noMax={noMax} />
  </header>;
}
export function CrystalWindow({ children, target = "main" }: {
  children: ReactNode; target?: "main" | "details"
}) {
  const { appearance, theme } = useCrystal();
  const frame=useRef<HTMLDivElement>(null);
  const [fit,setFit]=useState(1),[windowError,setWindowError]=useState(""),[maximized,setMaximized]=useState(false),[tiled,setTiled]=useState(false);
  useEffect(()=>{
    let active=true, sequence=0;let unlisten:(()=>void)|undefined;
    const update=()=>{const request=++sequence;const w=getCurrentWindow();void Promise.all([w.isMaximized(),w.outerPosition(),w.outerSize(),currentMonitor()]).then(([max,pos,size,monitor])=>{if(active&&request===sequence){setMaximized(max);setTiled(!max&&!!monitor&&isTiledWindow(pos,size,monitor.workArea))}}).catch(()=>{void w.isMaximized().then(value=>{if(active&&request===sequence)setMaximized(value)}).catch(()=>undefined)})};
    update();window.addEventListener('resize',update);
    void getCurrentWindow().onMoved(update).then(fn=>{if(active)unlisten=fn;else fn()}).catch(()=>undefined);
    return()=>{active=false;window.removeEventListener('resize',update);unlisten?.()};
  },[]);
  useEffect(()=>{const report=(event:Event)=>setWindowError(String((event as CustomEvent).detail));window.addEventListener("glass-window-error",report);return()=>window.removeEventListener("glass-window-error",report)},[]);
  useLayoutEffect(()=>{
    const el=frame.current;if(!el)return;
    let disposed=false,raf=0,resizing=false,resizeTimer=0;
    const baseScale=()=>appearance.uiScale/100;
    const measure=()=>{
      cancelAnimationFrame(raf);raf=requestAnimationFrame(()=>{
        if(disposed||resizing)return;
        const fit=el.querySelector<HTMLElement>('.cg-fit-content');if(!fit)return;
        let ratio=1;
        for(const box of [fit,...el.querySelectorAll<HTMLElement>('.cg-page,.cg-window-add,.cg-main-body,.cg-workspace,.cg-toolbar,.cg-window-top,.cg-original-editor')]){
          // The progress page scrolls intentionally when controls need more room.
          if(box.classList.contains('cg-minimal-progress'))continue;
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
    const resize=()=>{resizing=true;window.clearTimeout(resizeTimer);resizeTimer=window.setTimeout(()=>{resizing=false;reset()},120)};
    window.addEventListener('resize',resize);reset();
    return()=>{disposed=true;window.clearTimeout(resizeTimer);cancelAnimationFrame(raf);observer.disconnect();mutations.disconnect();el.removeEventListener('click',sectionClick);el.removeEventListener('change',reset);el.removeEventListener('toggle',reset,true);window.removeEventListener('resize',resize)};
  },[appearance.uiScale,appearance.fontSize,appearance.fontFamily,target]);
  const main = target === "main";
  const mode = main ? appearance.mainMode : appearance.detailMode;
  const solidColor = (main ? appearance.mainSolidColor : appearance.detailSolidColor) || defaultSolidColor(appearance.material, theme);
  const customMaterial=extraMaterials[appearance.material]??loadMaterials().find(m=>materialId(m)===appearance.material);
  const selectedMaterial = customMaterial ?? resolveMaterial(appearance.material);
  const surfaceStyle=materialBackdrop(appearance.material,selectedMaterial);
  const selectedBackdrop = nativeBackdrop(mode, surfaceStyle);
  // White palettes need light surfaces and dark foregrounds in every material.
  const blackGlass = appearance.material === "builtin-black-glass";
  const auroraDark = appearance.material === "builtin-aurora-night";
  const auroraLight = appearance.material === "builtin-aurora-ice";
  const effectiveLight = usesLightSurface(appearance.material, theme);
  const compositionQueue = useRef(Promise.resolve());
  useEffect(() => {
    const windowHandle = getCurrentWindow();
    const flat = maximized || tiled;
    let disposed = false;
    let pending = false;
    let timer = 0;
    let initialized = false;
    let stopFocusListener: (() => void) | undefined;

    const updateShape = () => {
      if (disposed || pending) return;
      pending = true;
      compositionQueue.current = compositionQueue.current.catch(() => undefined).then(async () => {
        pending = false;
        if (disposed) return;
        if (!selectedBackdrop && !initialized) {
          const cleared = await invoke<boolean>("set_material_acrylic", {enabled: false, dark: !effectiveLight}).catch(() => false);
          if (!cleared) await windowHandle.clearEffects().catch(() => undefined);
          if (disposed) return;
        }
        try {
          await invoke("set_material_window_shape", {flat});
        } catch (error) {
          if (disposed) return;
          await windowHandle.clearEffects().catch(() => undefined);
          if (!disposed) setWindowError(`Material outline unavailable: ${String(error)}`);
          return;
        }
        initialized = true;
        if (disposed || !selectedBackdrop) return;
        // The visible shell and native window region must agree before acrylic
        // is applied. Resizing can reset composition, so refresh it afterwards.
        try {
          const applied = await invoke<boolean>("set_material_acrylic", {enabled: true, dark: !effectiveLight});
          if (disposed || applied) return;
          await windowHandle.setEffects({
            effects: [selectedBackdrop === "blur" ? Effect.Blur : Effect.Acrylic],
            state: EffectState.Active,
          });
        } catch {
          if (disposed) return;
          await windowHandle.clearEffects().catch(() => undefined);
          if (!disposed) setWindowError("Windows backdrop blur is unavailable; transparent glass is being used.");
        }
      });
    };

    const onResize = () => {
      if (timer) return;
      timer = window.setTimeout(() => { timer = 0; updateShape(); }, 50);
    };
    window.addEventListener("resize", onResize);
    void windowHandle.onFocusChanged(onResize).then(unlisten => {
      if (disposed) unlisten();
      else stopFocusListener = unlisten;
    }).catch(() => undefined);
    updateShape();
    return () => {
      disposed = true;
      window.clearTimeout(timer);
      window.removeEventListener("resize", onResize);
      stopFocusListener?.();
    };
  }, [maximized, tiled, selectedBackdrop, effectiveLight]);
  const translucency = (appearance.glassTranslucency ?? selectedMaterial.translucency) / 100;
  const surfaceOpacity = 1 - translucency;
  const themeTintRgb=useMemo(()=>(appearance.material==="builtin-aurora-night"?[21,37,76]:appearance.material==="builtin-aurora-ice"?[225,244,255]:(theme.neutralTint??theme.rgb.split(",").map(Number))) as [number,number,number],[theme,appearance.material]);
  const path = main ? appearance.wallMain : (appearance.wallDetail || appearance.wallMain);
  const src = path ? convertFileSrc(path) : "/alpine.svg";
  const video = /\.(mp4|webm|mov|m4v)$/i.test(path);
  const lightAccentRgb = theme.light ? theme.rgb.split(",").map(v=>Math.round(Number(v)*.36)).join(",") : theme.id === "white-pearl" ? "101,86,67" : "64,91,112";
  const lightAccent = `rgb(${lightAccentRgb})`;
  const materialFace = materialSurfaceColor(appearance.material, theme, effectiveLight);
  const themeTint = Math.max(0, Math.min(65, appearance.tintStrength));
  const paneRgb = mixColor(materialFace, themeTintRgb, blackGlass ? 0 : themeTint * .0045);
  const style = {
    "--accent": auroraLight ? "#087eb8" : auroraDark ? "#46d8ff" : effectiveLight ? lightAccent : theme.accent,
    "--accent-secondary": auroraDark || auroraLight ? "#a752ff" : theme.secondary,
    "--palette-hue": auroraDark || auroraLight ? 210 : themeHue(theme),
    "--theme-action-rgb": effectiveLight ? lightAccentRgb : mixColor(theme.rgb.split(",").map(Number),[255,255,255],.20),
    "--theme-primary-rgb": effectiveLight ? lightAccentRgb : mixColor(theme.rgb.split(",").map(Number),[255,255,255],.10),
    "--theme-warn-rgb": effectiveLight ? lightAccentRgb : mixColor(theme.rgb.split(",").map(Number),secondaryRgb(theme),.55),
    "--theme-danger-rgb": effectiveLight ? lightAccentRgb : mixColor(theme.rgb.split(",").map(Number),secondaryRgb(theme),.80),
    "--theme-tool-rgb": effectiveLight ? lightAccentRgb : mixColor(secondaryRgb(theme),[255,255,255],.18),
    "--accent-rgb": auroraLight ? "8,126,184" : auroraDark ? "70,216,255" : effectiveLight ? lightAccentRgb : theme.rgb,
    "--glass": auroraDark ? "12,23,51" : auroraLight ? "225,244,255" : blackGlass ? "8,10,14" : effectiveLight ? themeTintRgb.join(",") : themeTintRgb.map(n=>Math.round(n*(theme.neutralTint ? .65 : .20))).join(","),
    "--glass-tint": auroraDark ? "rgba(36,68,152,.20)" : auroraLight ? "rgba(157,219,255,.20)" : blackGlass ? "rgba(0,0,0,0)" : `rgba(${(theme.neutralTint??theme.rgb.split(",").map(Number)).join(",")},${themeTint / 100})`,
    "--surface": auroraDark ? "rgba(41,65,120,.36)" : auroraLight ? "rgba(221,243,255,.66)" : blackGlass ? "rgba(12,14,18,.46)" : effectiveLight ? `rgba(${themeTintRgb.join(",")},.75)` : `rgba(${themeTintRgb.join(",")},.13)`,
    "--field": auroraDark ? "rgba(7,18,46,.78)" : auroraLight ? "rgba(239,251,255,.82)" : blackGlass ? "rgba(6,8,12,.78)" : effectiveLight ? `rgba(${themeTintRgb.join(",")},.92)` : `rgba(${themeTintRgb.map(n=>Math.round(n*.12)).join(",")},.82)`,
    "--popover": auroraDark ? "rgb(16,31,70)" : auroraLight ? "rgb(230,247,255)" : blackGlass ? "rgb(20,23,29)" : effectiveLight ? `rgb(${themeTintRgb.join(",")})` : `rgb(${themeTintRgb.map(n=>Math.round(n*(theme.neutralTint ? .65 : .18))).join(",")})`,
    "--material-face-rgb": (mode === "solid"
      ? [1, 3, 5].map(offset => parseInt(solidColor.slice(offset, offset + 2), 16))
      : materialFace).join(" "),
    "--material-pane-rgb": paneRgb.replaceAll(",", " "),
    "--glass-window-opacity": surfaceOpacity,
    "--glass-window-translucency": translucency,
    "--panel-opacity": surfaceOpacity,
    "--backdrop-opacity": surfaceOpacity,
    "--material-opacity": customMaterial ? surfaceOpacity : undefined,
    "--material-shading": customMaterial ? customMaterial.shading/100 : undefined,
    "--crystal-blur": appearance.blur + "px",
    "--ui-scale": 1,
    "--fit-scale": Math.max(.7,fit),
    "--font-family": ({"Segoe UI":"Segoe UI Variable, Segoe UI, sans-serif", "Inter":"Inter, Segoe UI, sans-serif", "Arial":"Arial, sans-serif", "Consolas":"Consolas, monospace", "Trebuchet MS":"Trebuchet MS, sans-serif", "Verdana":"Verdana, sans-serif", "Georgia":"Georgia, serif", "Candara":"Candara, sans-serif", "Century Gothic":"Century Gothic, sans-serif", "Palatino Linotype":"Palatino Linotype, serif", "Tahoma":"Tahoma, sans-serif"} as Record<string,string>)[appearance.fontFamily] ?? "Segoe UI Variable, Segoe UI, sans-serif",
    "--min-text-size": (12/Math.max(.4,fit))+"px",
    "--min-icon-size": (16/Math.min(1,Math.max(.4,fit)))+"px",
    "--min-window-button": (30/Math.min(1,Math.max(.4,fit)))+"px",
    "--font-size": Math.max(Math.min(20,Math.max(12,appearance.fontSize)),12/Math.max(.4,fit))+"px"
  } as CSSProperties;
  return <div className={`cg-window ${main?"cg-target-main":"cg-target-details"} cg-mode-${mode} ${selectedBackdrop ? "cg-native-backdrop" : ""} cg-material-${appearance.material} cg-surface-${surfaceStyle} cg-theme-${theme.id} ${theme.light&&effectiveLight?"cg-custom-light":""} ${customMaterial?`cg-custom-material cg-finish-${customMaterial.finish} cg-controls-${customMaterial.controls} cg-layout-${customMaterial.layout??'standard'} cg-text-${customMaterial.text??'crisp'}`:""} cg-progress-shape-${appearance.progressShape} cg-connection-shape-${appearance.connectionShape} ${maximized?"cg-maximized":""} ${tiled?"cg-tiled":""} ${effectiveLight?"cg-light":"cg-dark"} ${appearance.highContrast?"cg-high-contrast":""}`} style={style}>
    {mode === "wallpaper" && <div className="cg-wallpaper">
      {video ? <video key={src} autoPlay loop muted playsInline src={src} /> :
        <div style={{ backgroundImage: `url("${src}")` }} />}
      <span style={{ background: `rgba(3,9,19,${appearance.dim / 100})` }} />
    </div>}
    {mode === "solid" && <div className="cg-solid" style={{backgroundColor: solidColor}} />}
    <div className="cg-content" ref={frame}>
      {appearance.material === "frosted-water-351" &&
        <FrostedLayers tintHue={appearance.tintHue} tintRgb={themeTintRgb} tintStrength={appearance.tintStrength} opacity={surfaceOpacity * 100}/>}
      <div className="cg-fit-content">{children}</div>
    </div>
    {windowError&&<aside className="cg-window-notice cg-error" role="alert"><span>{windowError}</span><button title="Dismiss" onClick={()=>setWindowError("")}><X size={15}/></button></aside>}
    <ResizeGrips />
  </div>;
}
export function openWindow(label: string, url: string, width: number, height: number) {
  void invoke("open_glass_window",{label,url,width,height}).catch(e=>{
    window.dispatchEvent(new CustomEvent("glass-window-error",{detail:String(e)}));
  });
}
