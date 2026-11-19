import {useId} from "react";
import {sculptedPercent, sculptedPartPercent} from "./sculptedState";

// Curves traced from the supplied concept images. These are an initial vector
// implementation; their glass lighting still needs reference/Windows review.
export const sculptedShapes: Record<string,{label:string;path:string}> = {
  spiral:{label:"Spiral",path:"M 105 41 C 96 50 81 43 84 32 C 88 16 109 14 124 23 C 148 38 135 61 115 64 C 86 68 66 55 63 42"},
  clover:{label:"Clover loop",path:"M 99 17 C 75 8 68 29 77 36 C 86 43 57 48 69 61 C 78 71 97 65 107 57 C 121 48 128 55 128 55"},
  diamond:{label:"Rounded diamond",path:"M 86 64 C 72 57 52 50 53 40 C 54 28 82 14 101 14 C 118 14 148 30 148 40 C 148 49 128 57 114 64"},
  links:{label:"Glass links",path:"M 12 48 L 43 40 M 51 40 L 78 40 M 87 40 L 115 46 M 124 45 L 151 37 M 160 36 L 188 43"},
  switchback:{label:"Switchback",path:"M 25 16 H 169 C 192 16 192 40 169 40 H 30 C 8 40 8 64 30 64 H 170"},
  hourglass:{label:"Hourglass",path:"M 15 40 C 55 40 71 40 100 40 C 129 40 145 40 185 40"},
  figureeight:{label:"Figure eight",path:"M 103 48 C 81 33 63 10 47 19 C 26 31 32 62 48 63 C 64 65 81 50 96 40 C 119 26 137 12 153 19 C 177 28 168 62 150 63"},
  twinwave:{label:"Twin wave",path:"M 12 30 C 56 44 76 36 100 30 S 150 20 188 30 M 12 55 C 56 68 76 60 100 54 S 150 44 188 54"},
  scurve:{label:"S-curve",path:"M 12 40 C 49 52 62 55 100 43 S 151 23 188 40"},
  arch:{label:"Arch",path:"M 12 58 C 45 51 67 22 100 21 S 155 46 188 58"},
  steps:{label:"Soft steps",path:"M 12 61 H 43 C 61 61 64 42 80 42 H 119 C 135 42 138 22 157 22 H 188"},
  taperedwave:{label:"Tapered wave",path:"M 12 40 C 44 67 53 54 75 39 S 103 27 125 43 S 155 49 175 34 L 188 40"},
  hairpin:{label:"Hairpin",path:"M 25 20 H 165 C 190 20 190 60 165 60 H 25"},
  openring:{label:"Open ring",path:"M 83 62 C 59 43 75 13 100 13 C 125 13 141 43 117 62"}
};
export function isSculptedShape(id:string){return Object.hasOwn(sculptedShapes,id)}
export default function SculptedTrack({shape,percent,colors,lost=false,finish="default",tint="ice",tintColors,animate=true,compact=false}:{shape:string;percent:number;colors:string[];lost?:boolean;finish?:string;tint?:string;tintColors?:string[];animate?:boolean;compact?:boolean}){
 const id=useId().replace(/:/g,"-"),design=sculptedShapes[shape];if(!design)return null;
 const value=sculptedPercent(percent);
 const parts=design.path.split(/(?=M )/).filter(Boolean);
 const outline=shape==="hourglass"?"M 18 25 C 36 25 68 35 100 35 C 132 35 164 25 182 25 C 197 25 197 55 182 55 C 164 55 132 45 100 45 C 68 45 36 55 18 55 C 3 55 3 25 18 25 Z":shape==="taperedwave"?"M 10 34 C 38 56 48 54 68 35 C 88 16 102 21 122 36 C 141 51 150 43 171 31 C 180 26 187 31 192 36 L 187 45 C 179 42 176 40 171 42 C 153 54 140 63 119 50 C 99 37 90 33 78 46 C 54 69 38 68 7 46 Z":null;
 const trackColor=({ice:"#aacfe5",violet:"#c1a2ec",teal:"#77ded9",amber:"#f3c184"} as Record<string,string>)[tint]??"#aacfe5";
 const innerColor=finish==="frosted"?"#97b9cc":finish==="recessed"?"#12273b":finish==="clear"?"#3d7185":"#1d4b69";
 const valueFor=(index:number)=>sculptedPartPercent(value,parts.length,index,shape==="links");
 return <svg className={`cg-sculpted-track ${compact?"cg-sculpted-compact":"cg-sculpted-detailed"}`} viewBox="0 0 200 80" preserveAspectRatio="none" aria-hidden="true">
  <defs>
   {tintColors&&<linearGradient id={`${id}-track-tint`}><stop stopColor={tintColors[0]}/><stop offset=".5" stopColor={tintColors[1]}/><stop offset="1" stopColor={tintColors[2]}/></linearGradient>}
   <linearGradient id={`${id}-fill`} gradientUnits="userSpaceOnUse" x1="0" x2="200" y1="0" y2="80"><stop stopColor={colors[0]}/><stop offset=".5" stopColor={colors[1]}/><stop offset="1" stopColor={colors[2]}/></linearGradient>
   <linearGradient id={`${id}-gloss`} gradientUnits="userSpaceOnUse" x1="0" x2="0" y1="0" y2="80"><stop stopColor="#f4ffff" stopOpacity=".85"/><stop offset=".45" stopColor="#c2f9ff" stopOpacity=".12"/><stop offset="1" stopColor="#7be5ff" stopOpacity=".45"/></linearGradient>
   <linearGradient id={`${id}-rim`} x1="0" y1="0" x2="0" y2="1"><stop stopColor="#efffff" stopOpacity=".95"/><stop offset=".38" stopColor="#88c7e5" stopOpacity=".5"/><stop offset=".72" stopColor="#173d5e" stopOpacity=".85"/><stop offset="1" stopColor="#c2faff" stopOpacity=".92"/></linearGradient>
   <linearGradient id={`${id}-depth`} x1="0" x2="0" y1="0" y2="1"><stop stopColor="#ecffff" stopOpacity=".72"/><stop offset=".24" stopColor="#81dff3" stopOpacity=".13"/><stop offset=".68" stopColor="#133653" stopOpacity=".30"/><stop offset="1" stopColor="#97f8ff" stopOpacity=".75"/></linearGradient>
   {outline&&<clipPath id={`${id}-outline`}><path d={outline}/></clipPath>}
   <mask id={`${id}-fill-mask`} maskUnits="userSpaceOnUse" x="0" y="0" width="200" height="80">{parts.map((path,index)=>valueFor(index)>0&&<path key={index} d={path} pathLength="100" strokeDasharray={`${valueFor(index)} 100`} fill="none" stroke="white" strokeWidth={outline?"35":"18"} strokeLinecap="round" strokeLinejoin="round"/>)}</mask>
  </defs>
  {outline?<g><path d={outline} fill="#05283e" fillOpacity=".40" transform="translate(0 2)"/><path d={outline} fill={lost?"#b61b37":innerColor} fillOpacity=".7" stroke={lost?"#ff6981":trackColor} strokeWidth="1.6"/>{!lost&&<><path d={outline} fill={tintColors?`url(#${id}-track-tint)`:trackColor} fillOpacity=".45"/><path d={outline} fill={`url(#${id}-depth)`} opacity=".7"/></>}<path d={outline} fill={`url(#${id}-fill)`} mask={`url(#${id}-fill-mask)`}/><path d={outline} fill={`url(#${id}-depth)`} mask={`url(#${id}-fill-mask)`}/></g>:parts.map((path,index)=>{const partValue=valueFor(index);return <g key={index}>
   <path d={path} transform="translate(0 2)" fill="none" stroke="#031d32" strokeOpacity=".45" strokeWidth="25" strokeLinecap="round" strokeLinejoin="round"/>
   <path d={path} fill="none" stroke={lost?"#e63350":trackColor} strokeOpacity={lost?.95:.6} strokeWidth="22" strokeLinecap="round" strokeLinejoin="round"/>
   {!lost&&<path d={path} fill="none" stroke={`url(#${id}-rim)`} strokeWidth="20" strokeLinecap="round" strokeLinejoin="round"/>}
   <path d={path} fill="none" stroke={lost?"#b61b37":innerColor} strokeOpacity=".90" strokeWidth="17" strokeLinecap="round" strokeLinejoin="round"/>
   {!lost&&<path d={path} fill="none" stroke={tintColors?`url(#${id}-track-tint)`:trackColor} strokeOpacity=".45" strokeWidth="17" strokeLinecap="round" strokeLinejoin="round"/>}
   {!lost&&<path d={path} fill="none" stroke={`url(#${id}-depth)`} strokeWidth="17" strokeLinecap="round" strokeLinejoin="round"/>}
   {partValue>0&&<><path d={path} pathLength="100" strokeDasharray={`${partValue} 100`} fill="none" stroke={`url(#${id}-fill)`} strokeWidth="18" strokeLinecap="round" strokeLinejoin="round"/><path d={path} pathLength="100" strokeDasharray={`${partValue} 100`} fill="none" stroke={`url(#${id}-gloss)`} strokeWidth="15" strokeLinecap="round" strokeLinejoin="round"/></>}
  </g>})}
  {value>0&&<g className={animate?"cg-sculpted-lighting":""} mask={`url(#${id}-fill-mask)`} clipPath={outline?`url(#${id}-outline)`:undefined} fill="none" strokeLinecap="round">
   <path className="cg-sculpted-reflection" d="M -20 15 C 15 1 24 57 58 41 S 91 22 116 42 S 151 53 179 29 S 207 28 220 37" stroke="#eaffff" strokeOpacity=".48" strokeWidth="1.2"/>
   <path d="M -20 24 C 10 14 27 61 57 49 S 87 28 115 51 S 152 60 178 37 S 206 36 220 45" stroke="#75e9ff" strokeOpacity=".50" strokeWidth="2"/>
   <path d="M -20 28 C 10 18 24 54 48 45 S 76 20 105 38 S 136 58 164 40 S 198 28 220 42" stroke="#f6ffff" strokeOpacity=".30" strokeWidth=".7"/>
  </g>}
  {value>0&&!outline&&parts.map((path,index)=><g key={`edges-${index}`} mask={`url(#${id}-fill-mask)`} fill="none" strokeLinecap="round" strokeLinejoin="round"><path d={path} transform="translate(0 -5)" stroke="#f2ffff" strokeOpacity=".72" strokeWidth="2.3"/><path d={path} transform="translate(0 5)" stroke="#71eaff" strokeOpacity=".7" strokeWidth="2.1"/></g>)}
  {animate&&value>0&&parts.map((path,index)=><path key={`shine-${index}`} className="cg-sculpted-sweep" d={path} pathLength="100" strokeDasharray="8 92" fill="none" stroke="#eaffff" strokeWidth="3" strokeLinecap="round" mask={`url(#${id}-fill-mask)`} clipPath={outline?`url(#${id}-outline)`:undefined}/>)}
 </svg>;
}
