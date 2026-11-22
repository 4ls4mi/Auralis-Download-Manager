import {useId} from 'react';

/** A lobed glass vessel. The same outline clips both the liquid and the empty track. */
export function BubbleProgress({percent,colors,backdrop,active}:{percent:number;colors:string[];backdrop?:readonly string[];active:boolean}) {
 const id=useId().replace(/:/g,'');
 const amount=Math.max(0,Math.min(100,Number.isFinite(percent)?percent:0));
 const a=colors[0]||'#06cfff',b=colors[1]||'#315bff',c=colors[2]||'#b94dff';
 const glass=backdrop?.[1]||'#42678d';
 const outline='M 4 50 C 4 12 24 4 46 7 C 80 10 92 32 130 32 C 166 32 179 15 215 14 C 251 13 267 34 304 34 C 341 34 356 8 395 8 C 435 8 450 32 486 32 C 523 32 536 17 573 17 C 611 17 627 33 663 33 C 700 33 714 16 752 16 C 789 16 806 33 841 33 C 878 33 892 7 931 7 C 971 7 996 18 996 50 C 996 82 971 93 931 93 C 892 93 878 67 841 67 C 806 67 789 84 752 84 C 714 84 700 67 663 67 C 627 67 611 83 573 83 C 536 83 523 68 486 68 C 450 68 435 92 395 92 C 356 92 341 66 304 66 C 267 66 251 87 215 86 C 179 85 166 68 130 68 C 92 68 80 90 46 93 C 24 96 4 88 4 50 Z';
 return <svg className={'cg-bubble-vessel'+(active?' cg-bubble-active':'')} viewBox="0 0 1000 100" preserveAspectRatio="none" aria-hidden="true">
  <defs>
   <clipPath id={id+'outline'}><path d={outline}/></clipPath>
   <clipPath id={id+'fill'}><rect x="0" y="0" width={amount*10} height="100"/></clipPath>
   <linearGradient id={id+'empty'} x1="0" y1="0" x2="0" y2="1"><stop stopColor="#e7f7ff" stopOpacity=".72"/><stop offset=".17" stopColor={glass} stopOpacity=".54"/><stop offset=".54" stopColor="#10203e" stopOpacity=".88"/><stop offset=".84" stopColor={glass} stopOpacity=".50"/><stop offset="1" stopColor="#e4faff" stopOpacity=".66"/></linearGradient>
   <linearGradient id={id+'color'} x1="0" y1="0" x2="1" y2="0"><stop stopColor={a}/><stop offset=".5" stopColor={b}/><stop offset="1" stopColor={c}/></linearGradient>
   <linearGradient id={id+'light'} x1="0" y1="0" x2="0" y2="1"><stop stopColor="#fff" stopOpacity=".72"/><stop offset=".24" stopColor="#fff" stopOpacity=".05"/><stop offset=".62" stopColor="#001343" stopOpacity=".18"/><stop offset=".87" stopColor="#c9ffff" stopOpacity=".32"/><stop offset="1" stopColor="#e7ffff" stopOpacity=".62"/></linearGradient>
   <radialGradient id={id+'bubble'} cx=".3" cy=".2" r=".8"><stop stopColor="#fff" stopOpacity=".88"/><stop offset=".2" stopColor={a} stopOpacity=".34"/><stop offset=".8" stopColor={b} stopOpacity=".18"/><stop offset="1" stopColor="#fff" stopOpacity=".75"/></radialGradient>
  </defs>
  <path d={outline} fill={`url(#${id}empty)`} stroke="#cceeff" strokeOpacity=".65" strokeWidth="3" vectorEffect="non-scaling-stroke"/>
  <g clipPath={`url(#${id}outline)`}><g clipPath={`url(#${id}fill)`}>
   <rect width="1000" height="100" fill={`url(#${id}color)`}/><rect width="1000" height="100" fill={`url(#${id}light)`}/>
   <path className="cg-bubble-wave" d="M0 61 C90 36 130 79 215 59 S350 40 425 60 S560 77 640 55 S765 39 850 61 S960 75 1000 57" fill="none" stroke="#e6ffff" strokeOpacity=".44" strokeWidth="3" vectorEffect="non-scaling-stroke"/>
   <circle cx="240" cy="50" r="12" fill={`url(#${id}bubble)`} stroke="#e8ffff" strokeOpacity=".68" strokeWidth="1.3" vectorEffect="non-scaling-stroke"/><circle cx="520" cy="57" r="9" fill={`url(#${id}bubble)`} stroke="#e8ffff" strokeOpacity=".68" strokeWidth="1.1" vectorEffect="non-scaling-stroke"/>
  </g></g>
  <path d={outline} fill="none" stroke="#e9ffff" strokeOpacity=".64" strokeWidth="2" vectorEffect="non-scaling-stroke"/>
  <path d="M23 31 C32 12 55 14 73 21 M179 32 C195 20 219 20 235 26 M366 29 C381 15 408 14 425 23 M904 30 C919 16 944 16 961 25" fill="none" stroke="#fff" strokeOpacity=".8" strokeWidth="3" strokeLinecap="round" vectorEffect="non-scaling-stroke"/>
 </svg>;
}
