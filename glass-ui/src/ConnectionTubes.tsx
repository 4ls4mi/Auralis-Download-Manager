import {useEffect,useId,useState} from 'react';
import type {CSSProperties,RefObject} from 'react';
import {lastReceivingRows} from './tubeNetwork';

type Size={width:number;height:number;gapX:number;gapY:number;padTop:number;padLeft:number;padRight:number};
/** Decorative plumbing sits behind cells. Active branches come only from real receiving workers. */
export function ConnectionTubes({container,slots,colors}:{container:RefObject<HTMLDivElement|null>;slots:boolean[];colors:string[]}){
 const [size,setSize]=useState<Size>({width:0,height:0,gapX:4,gapY:4,padTop:14,padLeft:0,padRight:0}),id=useId().replace(/:/g,'');
 useEffect(()=>{const node=container.current;if(!node)return;const measure=()=>{const css=getComputedStyle(node);setSize({width:node.clientWidth,height:node.clientHeight,gapX:parseFloat(css.columnGap)||0,gapY:parseFloat(css.rowGap)||0,padTop:parseFloat(css.paddingTop)||0,padLeft:parseFloat(css.paddingLeft)||0,padRight:parseFloat(css.paddingRight)||0})};const ro=new ResizeObserver(measure);ro.observe(node);measure();return()=>ro.disconnect()},[container]);
 const {width,height,gapX,gapY,padTop,padLeft,padRight}=size;
 if(width<=0||height<=padTop)return null;
 const cellW=Math.max(0,(width-padLeft-padRight-7*gapX)/8),cellH=Math.max(0,(height-padTop-3*gapY)/4);
 const xs=Array.from({length:8},(_,i)=>padLeft+i*(cellW+gapX)+cellW/2);
 const head=padTop*.45,last=lastReceivingRows(slots);
 // Stop inside each cell and resume in the next gap, so the tubes appear to
 // enter the top of the glass rather than run along its side or through it.
 const segment=(col:number,row:number)=>{const y=padTop+row*(cellH+gapY);return `M${xs[col]} ${row===0?head:y-gapY-1} V${y+1}`};
 const header=`M${xs[0]} ${head} H${xs[7]}`;
 return <svg className="cg-connection-tubes" viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id={id} gradientUnits="userSpaceOnUse" x1="0" x2={width} y1="0" y2="0"><stop stopColor={colors[0]}/><stop offset=".5" stopColor={colors[1]}/><stop offset="1" stopColor={colors[2]}/></linearGradient></defs>
  <path className="cg-tube-shell" d={header}/>{slots.map((_,slot)=><path key={slot} className="cg-tube-shell" d={segment(slot%8,Math.floor(slot/8))}/>)}
  {last.map((row,i)=>row>=0&&<g key={i} data-active-column={i}><path className="cg-tube-liquid" d={`M${xs[0]} ${head} H${xs[i]}`} stroke={`url(#${id})`}/><path className="cg-tube-flow" d={`M${xs[0]} ${head} H${xs[i]}`} stroke="rgba(235,255,255,.9)"/>{Array.from({length:row+1},(_,r)=><g key={r}><path className="cg-tube-liquid" d={segment(i,r)} stroke={`url(#${id})`}/><path className="cg-tube-flow" d={segment(i,r)} stroke="rgba(235,255,255,.9)"/></g>)}</g>)}
  {slots.map((active,slot)=>active&&<g key={slot} data-active-slot={slot}/>)}
 </svg>;
}

type BridgeGeometry={w:number;h:number;urlX:number;urlY:number;barX:number;barY:number;barTop:number;barRight:number;barBottom:number;gridX:number;gridY:number;left:number};
/** Routes the URL → progress → distribution feed, in the scrollable page's own coordinates. */
export function TubeBridge({container,active,colors,progressColors,ready}:{container:RefObject<HTMLElement|null>;active:boolean;colors:string[];progressColors:string[];ready:boolean}){
 const [g,setGeometry]=useState<BridgeGeometry|null>(null),id=useId().replace(/:/g,'');
 useEffect(()=>{const root=container.current;if(!root||!ready){setGeometry(null);return}const url=root.querySelector<HTMLElement>('.cg-mdm-details'),bar=root.querySelector<HTMLElement>('.cg-overall .cg-percent-track'),grid=root.querySelector<HTMLElement>('.cg-fixed-connections');if(!url||!bar||!grid){setGeometry(null);return}
  const measure=()=>{const base=root.getBoundingClientRect(),r1=url.getBoundingClientRect(),r2=bar.getBoundingClientRect(),r3=grid.getBoundingClientRect(),sx=base.width/Math.max(root.offsetWidth,1),sy=base.height/Math.max(root.offsetHeight,1);if(!sx||!sy)return;const X=(x:number)=>(x-base.left)/sx+root.scrollLeft,Y=(y:number)=>(y-base.top)/sy+root.scrollTop;const urlX=X(r1.left),barX=X(r2.left),css=getComputedStyle(grid),gap=parseFloat(css.columnGap)||0,padL=parseFloat(css.paddingLeft)||0,padR=parseFloat(css.paddingRight)||0,cell=(grid.clientWidth-padL-padR-7*gap)/8;setGeometry({w:root.clientWidth,h:root.scrollHeight,urlX,urlY:Y(r1.top+Math.min(r1.height*.25,24)),barX,barY:Y(r2.top+r2.height*.5),barTop:Y(r2.top),barRight:X(r2.right),barBottom:Y(r2.bottom),gridX:X(r3.left)+(padL+cell/2),gridY:Y(r3.top)+(parseFloat(css.paddingTop)||0)*.45,left:Math.max(2,Math.min(urlX,barX)-7)})};
  const ro=new ResizeObserver(measure);for(const el of [root,url,bar,grid])ro.observe(el);measure();return()=>ro.disconnect();
 },[container,ready]);
 if(!g)return null;const inlet=`M${g.urlX+6} ${g.urlY} H${g.left+4} Q${g.left} ${g.urlY} ${g.left} ${g.urlY+4} V${Math.max(g.urlY+4,g.barY-4)} Q${g.left} ${g.barY} ${g.left+4} ${g.barY} H${g.barX+6}`;
 const feed=`M${g.barX+6} ${g.barY} H${g.left+4} Q${g.left} ${g.barY} ${g.left} ${g.barY+4} V${g.gridY-4} Q${g.left} ${g.gridY} ${g.left+4} ${g.gridY} H${g.gridX}`;
 return <svg className="cg-tube-bridge" width={g.w} height={g.h} viewBox={`0 0 ${g.w} ${g.h}`} aria-hidden="true" style={{'--cg-tube-a':colors[0],'--cg-tube-b':colors[1],'--cg-tube-c':colors[2]} as CSSProperties}><defs><linearGradient id={id} x1="0" x2="1" y1="0" y2="0"><stop stopColor={colors[0]}/><stop offset=".5" stopColor={colors[1]}/><stop offset="1" stopColor={colors[2]}/></linearGradient><linearGradient id={`${id}p`} x1="0" x2="1" y1="0" y2="0"><stop stopColor={progressColors[0]}/><stop offset=".5" stopColor={progressColors[1]}/><stop offset="1" stopColor={progressColors[2]}/></linearGradient><mask id={`${id}m`} maskUnits="userSpaceOnUse"><rect width={g.w} height={g.h} fill="white"/><rect x={g.urlX} y={g.urlY-8} width="12" height="16" fill="black"/><rect x={g.barX} y={g.barTop} width={g.barRight-g.barX} height={g.barBottom-g.barTop} fill="black"/></mask></defs><g mask={`url(#${id}m)`}><path className="cg-tube-shell" d={inlet}/><path className="cg-tube-shell" d={feed}/>{active&&<><path className="cg-tube-liquid" d={inlet} stroke={`url(#${id}p)`}/><path className="cg-tube-flow" d={inlet} stroke="rgba(235,255,255,.9)"/><path className="cg-tube-liquid" d={feed} stroke={progressColors[1]}/><path className="cg-tube-flow" d={feed} stroke="rgba(235,255,255,.9)"/></>}</g></svg>;
}
