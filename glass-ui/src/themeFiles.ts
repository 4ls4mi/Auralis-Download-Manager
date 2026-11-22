import {parseMaterial, type MaterialFile} from './customMaterials.ts';

// Theme files are data only. They deliberately cannot contain CSS, scripts,
// local wallpaper paths, or arbitrary URLs.
export type ThemePalette = {name:string;accent:string;secondary:string;surface:[number,number,number]|null;light:boolean};
export type ThemeSettings = {
  tintStrength:number; fontFamily:string; fontSize:number; highContrast:boolean; uiScale:number; dim:number; blur:number;
  indicator:string; connectionIndicator:string; graphIndicator:string;
  progressMaterial:string; connectionMaterial:string; graphMaterial:string;
  progressShape:string; connectionShape:string; graphShape:string;
  trackFinish:string; trackColor:string; connectionTrackFinish:string; connectionTrackColor:string;
};
export type ThemeFile = {format:'auralis-theme';version:1;palette:ThemePalette;material:string;customMaterial:MaterialFile|null;settings:ThemeSettings};
export const THEMES_KEY='mh-glass-custom-themes';
const indicators=['blue-purple','ocean','sunset','aurora','silver','cobalt','emerald','tangerine','coral','violet','lime','candy','arctic','fire','forest','neon'];
const liquid=['liquid-glass','liquid-crystal','liquid-aero'];
const choice:Record<string,string[]>={
  indicator:indicators,connectionIndicator:indicators,graphIndicator:indicators,
  progressMaterial:['gradient','frosted-ribbon',...liquid],connectionMaterial:['gradient',...liquid],graphMaterial:['gradient',...liquid],
  progressShape:['rounded','faceted','droplet','bubble','square'],connectionShape:['rounded','faceted','droplet','bubble','square'],graphShape:['area','line','bars'],
  trackFinish:['default','clear','frosted','recessed'],connectionTrackFinish:['default','clear','frosted','recessed'],
  trackColor:['ice','violet','teal','amber',...indicators.map(id=>`palette:${id}`)],connectionTrackColor:['ice','violet','teal','amber',...indicators.map(id=>`palette:${id}`)],
  fontFamily:['Segoe UI','Inter','Arial','Consolas','Trebuchet MS','Verdana','Georgia','Candara','Century Gothic','Palatino Linotype','Tahoma']
};
const builtinMaterials=['brushed-glass','frosted-water-351','rose-pine','window-glass','oversimplified','builtin-obsidian-matte','builtin-smoked-glass','builtin-black-glass','builtin-pearl-frost','builtin-aurora-night','builtin-aurora-ice'];
const object=(v:unknown):Record<string,unknown>=>{if(!v||typeof v!=='object'||Array.isArray(v))throw Error('Expected a JSON object.');return v as Record<string,unknown>};
export function parseTheme(input:unknown):ThemeFile {
 const v=object(input);if(v.format!=='auralis-theme'||v.version!==1)throw Error('Expected an Auralis theme file (version 1).');
 const p=object(v.palette);if(typeof p.name!=='string'||!p.name.trim()||p.name.trim().length>50)throw Error('Theme name must contain 1–50 characters.');
 if(typeof p.accent!=='string'||!/^#[0-9a-f]{6}$/i.test(p.accent)||typeof p.secondary!=='string'||!/^#[0-9a-f]{6}$/i.test(p.secondary))throw Error('Colors must be six-digit hex values, such as #33AAFF.');
 if(p.surface!==null&&(!Array.isArray(p.surface)||p.surface.length!==3||p.surface.some(x=>!Number.isInteger(x)||x<0||x>255)))throw Error('Surface must be null or three RGB numbers from 0 to 255.');
 if(typeof p.light!=='boolean')throw Error('The light option must be true or false.');
 if(p.light&&p.surface===null)throw Error('Light themes need an explicit light surface color.');
 if(Array.isArray(p.surface)){const brightness=.2126*p.surface[0]+.7152*p.surface[1]+.0722*p.surface[2];if((p.light&&brightness<150)||(!p.light&&brightness>190))throw Error('Set light to match the surface brightness so text remains readable.')}
 if(typeof v.material!=='string')throw Error('Invalid material.');
 const custom=v.customMaterial===null?null:parseMaterial(v.customMaterial);
 if(custom ? v.material!=='custom' : !builtinMaterials.includes(v.material))throw Error('Unknown surface material.');
 const s=object(v.settings);const out:Record<string,unknown>={};
 for(const [key,values] of Object.entries(choice)){if(typeof s[key]!=='string'||!values.includes(s[key] as string))throw Error(`Invalid ${key}.`);out[key]=s[key]}
 for(const [key,min,max] of [['tintStrength',0,65],['fontSize',12,20],['uiScale',80,150],['dim',0,80],['blur',0,20]] as const){const n=s[key];if(typeof n!=='number'||!Number.isFinite(n)||n<min||n>max)throw Error(`Invalid ${key}.`);out[key]=n}
 if(typeof s.highContrast!=='boolean')throw Error('Invalid highContrast.');out.highContrast=s.highContrast;
 return {format:'auralis-theme',version:1,palette:{name:p.name.trim(),accent:p.accent.toLowerCase(),secondary:p.secondary.toLowerCase(),surface:p.surface as ThemePalette['surface'],light:p.light},material:v.material,customMaterial:custom,settings:out as ThemeSettings};
}
export function themeId(p:ThemePalette){return 'user-'+Array.from(new TextEncoder().encode(p.name.toLowerCase())).map(n=>n.toString(16).padStart(2,'0')).join('')}
export function loadThemes():ThemeFile[]{try{const v=JSON.parse(localStorage.getItem(THEMES_KEY)||'[]');return Array.isArray(v)?v.slice(0,32).map(parseTheme):[]}catch{return []}}
export function paletteForTheme(p:ThemePalette){return {id:themeId(p),name:p.name,accent:p.accent,secondary:p.secondary,rgb:[1,3,5].map(i=>parseInt(p.accent.slice(i,i+2),16)).join(','),...(p.surface?{neutralTint:p.surface}:{}),light:p.light}}
