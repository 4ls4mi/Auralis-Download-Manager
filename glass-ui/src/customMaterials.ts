/** Declarative material format: no scripts, selectors, external resources, or raw CSS. */
export type Finish='matte'|'satin'|'gloss'|'frosted'|'clear';
export type Shape='rounded'|'soft'|'angular';
export type MaterialFile={format:'auralis-material';version:1;name:string;finish:Finish;controls:Shape;translucency:number;shading:number;layout?:'compact'|'standard'|'spacious';text?:'crisp'|'soft'};
export const MATERIALS_KEY='mh-glass-custom-materials';
export function parseMaterial(input:unknown):MaterialFile {
 if(!input||typeof input!=='object'||Array.isArray(input))throw Error('Material must be a JSON object.');
 const v=input as Record<string,unknown>;
 if(v.format!=='auralis-material'||v.version!==1)throw Error('Expected an Auralis material file (version 1).');
 if(typeof v.name!=='string'||v.name.trim().length<1||v.name.trim().length>50)throw Error('Name must contain 1–50 characters.');
 if(!['matte','satin','gloss','frosted','clear'].includes(String(v.finish)))throw Error('Finish must be matte, satin, gloss, frosted, or clear.');
 if(!['rounded','soft','angular'].includes(String(v.controls)))throw Error('Controls must be rounded, soft, or angular.');
 if(v.layout!==undefined&&!['compact','standard','spacious'].includes(String(v.layout)))throw Error('Layout must be compact, standard, or spacious.');
 if(v.text!==undefined&&!['crisp','soft'].includes(String(v.text)))throw Error('Text must be crisp or soft.');
 for(const k of ['translucency','shading'])if(typeof v[k]!=='number'||!Number.isFinite(v[k])||v[k]<0||v[k]>100)throw Error(`${k} must be a number from 0 to 100.`);
 return {format:'auralis-material',version:1,name:v.name.trim(),finish:v.finish as Finish,controls:v.controls as Shape,translucency:v.translucency as number,shading:v.shading as number,...(v.layout?{layout:v.layout as MaterialFile['layout']} : {}),...(v.text?{text:v.text as MaterialFile['text']} : {})};
}
export function materialId(m:MaterialFile){return 'custom-'+Array.from(new TextEncoder().encode(m.name.toLowerCase())).map(n=>n.toString(16).padStart(2,'0')).join('')}
export function loadMaterials():MaterialFile[]{try{const v=JSON.parse(localStorage.getItem(MATERIALS_KEY)||'[]');return Array.isArray(v)?v.slice(0,32).map(parseMaterial):[]}catch{return []}}
export const materialPresets:Record<string,MaterialFile>={
 'brushed-glass':{format:'auralis-material',version:1,name:'Brushed Glass',finish:'satin',controls:'angular',translucency:35,shading:55},
 'frosted-water-351':{format:'auralis-material',version:1,name:'Frosted Layers',finish:'frosted',controls:'rounded',translucency:45,shading:70},
 'rose-pine':{format:'auralis-material',version:1,name:'Rose Pine',finish:'matte',controls:'soft',translucency:15,shading:35},
 'window-glass':{format:'auralis-material',version:1,name:'Window Glass',finish:'clear',controls:'angular',translucency:65,shading:40},
 'oversimplified':{format:'auralis-material',version:1,name:'Oversimplified & Accentuated',finish:'matte',controls:'rounded',translucency:10,shading:20}
};
export const extraMaterials:Record<string,MaterialFile>={
 'builtin-aurora-night':{format:'auralis-material',version:1,name:'Aurora Glass — Dark',finish:'frosted',controls:'angular',translucency:65,shading:55},
 'builtin-aurora-ice':{format:'auralis-material',version:1,name:'Aurora Glass — Light',finish:'frosted',controls:'angular',translucency:65,shading:30},
 'builtin-obsidian-matte':{format:'auralis-material',version:1,name:'Matte Obsidian',finish:'matte',controls:'angular',translucency:8,shading:75},
 'builtin-smoked-glass':{format:'auralis-material',version:1,name:'Smoked Glass',finish:'clear',controls:'soft',translucency:65,shading:65},
 'builtin-black-glass':{format:'auralis-material',version:1,name:'Black Blur Glass',finish:'clear',controls:'soft',translucency:72,shading:20},
 'builtin-pearl-frost':{format:'auralis-material',version:1,name:'Pearl Frost',finish:'frosted',controls:'rounded',translucency:35,shading:60}
};

/** Backdrop behavior belongs to the chosen material, not a separate toggle. */
export function materialBackdrop(id:string, material:MaterialFile): 'material'|'clear'|'soft'|'frosted'|'tinted' {
 if(id==='builtin-smoked-glass'||id==='builtin-black-glass')return 'tinted';
 switch(material.finish){
  case 'frosted': return 'frosted';
  case 'satin': case 'gloss': return 'soft';
  case 'clear': return 'clear';
  case 'matte': return 'material';
 }
}
