import {useId} from 'react';

// Scalable vector geometry sits behind controls and does not affect hit testing.
// The desktop backdrop is provided separately by Windows; this is not refraction.
const paths:Record<string,string>={
  'ice-edge':'M 4 16 L 18 2 L 965 2 L 996 27 L 996 474 L 973 498 L 25 498 L 4 477 Z',
  'diamond-facet':'M 22 2 L 978 2 L 998 24 L 998 476 L 978 498 L 22 498 L 2 476 L 2 24 Z',
  'prismatic-glass':'M 22 2 L 980 2 L 998 22 L 998 476 L 977 498 L 22 498 L 2 478 L 2 22 Z',
  'water-bubble':'M 48 8 C 180 -1 280 14 390 8 C 520 0 642 13 752 7 C 862 0 996 3 996 48 L 996 448 C 996 490 944 502 855 492 C 734 480 645 498 524 491 C 405 483 302 502 185 493 C 78 500 4 493 4 450 L 4 52 C 4 25 17 12 48 8 Z',
  'liquid-glass':'M 42 5 C 170 -3 310 16 480 6 C 672 -3 834 12 958 6 Q 996 6 996 45 L 996 455 Q 996 495 955 495 C 820 502 680 486 520 495 C 340 503 180 487 45 495 Q 4 495 4 455 L 4 45 Q 4 5 42 5 Z',
  'aero-gloss':'M 36 3 H 964 Q 997 3 997 36 V 464 Q 997 497 964 497 H 36 Q 3 497 3 464 V 36 Q 3 3 36 3 Z',
  'frosted-layers':'M 27 4 H 973 Q 996 4 996 27 V 473 Q 996 496 973 496 H 27 Q 4 496 4 473 V 27 Q 4 4 27 4 Z',
};
const angular=new Set(['ice-edge','diamond-facet','prismatic-glass','holographic-film']);
export default function MaterialSurface({material}:{material:string}){
 const id=useId().replace(/:/g,'');
 const path=paths[material]??paths['frosted-layers'];
 const liquid=material==='water-bubble'||material==='liquid-glass';
 const prism=material==='prismatic-glass'||material==='holographic-film';
 return <svg className="cg-material-surface" viewBox="0 0 1000 500" preserveAspectRatio="none" aria-hidden="true" focusable="false">
  <defs>
   <linearGradient id={`${id}-edge`} x1="0" y1="0" x2="1" y2="1"><stop stopColor={prism?'#72ffed':'#e7ffff'} stopOpacity=".8"/><stop offset=".38" stopColor="#8ccfff" stopOpacity=".12"/><stop offset=".72" stopColor={prism?'#ef8dff':'#c2ddff'} stopOpacity=".35"/><stop offset="1" stopColor={prism?'#ffd17a':'#d5f7ff'} stopOpacity=".7"/></linearGradient>
   <linearGradient id={`${id}-gloss`} x1="0" y1="0" x2="0" y2="1"><stop stopColor="#efffff" stopOpacity=".22"/><stop offset=".22" stopColor="#bfeaff" stopOpacity=".03"/><stop offset=".75" stopColor="#7bbfff" stopOpacity="0"/><stop offset="1" stopColor="#c2edff" stopOpacity=".12"/></linearGradient>
  </defs>
  <path d={path} fill={`url(#${id}-gloss)`} stroke={`url(#${id}-edge)`} strokeWidth="2" vectorEffect="non-scaling-stroke"/>
  {liquid&&<><path d="M 22 52 C 210 -2 297 48 486 22 S 805 40 978 20" fill="none" stroke="#dcffff" strokeOpacity=".42" strokeWidth="2" vectorEffect="non-scaling-stroke"/><path d="M 26 465 C 192 498 322 455 510 481 S 826 451 977 468" fill="none" stroke="#a4f9ff" strokeOpacity=".3" strokeWidth="2" vectorEffect="non-scaling-stroke"/></>}
  {angular.has(material)&&<><path d="M 4 75 L 68 2 M 780 2 L 675 94 L 875 40 L 960 2 M 996 420 L 920 498" fill="none" stroke={`url(#${id}-edge)`} strokeWidth="1.5" vectorEffect="non-scaling-stroke"/><path d="M 780 2 L 675 94 L 875 40 L 960 2 Z" fill="#bceaff" fillOpacity=".07"/></>}
  {material==='smoked-crystal'&&<path d="M 12 14 H 985 V 487 H 12 Z M 23 25 H 974 V 476 H 23 Z" fill="none" stroke="#b8d7ff" strokeOpacity=".18" vectorEffect="non-scaling-stroke"/>}
  {material==='frosted-layers'&&<path d="M 25 88 C 240 40 760 130 975 55 L 975 8 L 25 8 Z" fill="#fff" fillOpacity=".055"/>}
 </svg>;
}
