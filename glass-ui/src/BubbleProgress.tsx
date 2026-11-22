import {useId} from 'react';
import {isLiquidMaterial, LiquidProgress} from './LiquidIndicators';

// Four rounded chambers in one continuous silhouette. The outline has one
// upper edge and one lower edge throughout, including at the narrower joins.
const vessel = [
  'M4 50 C4 23 27 9 66 9 C120 9 142 32 199 32',
  'C249 32 272 11 324 11 C378 11 400 29 455 30',
  'C516 31 542 10 603 10 C667 10 690 32 750 32',
  'C812 32 846 8 913 8 C966 8 996 23 996 50',
  'C996 77 966 92 913 92 C846 92 812 68 750 68',
  'C690 68 667 90 603 90 C542 90 516 69 455 70',
  'C400 71 378 89 324 89 C272 89 249 68 199 68',
  'C142 68 120 91 66 91 C27 91 4 77 4 50 Z',
].join(' ');
const reflectedLight = [
  'M27 37 C47 19 81 15 109 24 C78 20 51 26 33 39 Q27 43 27 37 Z',
  'M273 34 C290 21 321 16 352 24 C322 21 294 28 278 38 Q272 41 273 34 Z',
  'M550 35 C570 18 605 15 637 23 C606 20 573 26 555 39 Q549 43 550 35 Z',
  'M865 35 C888 18 920 12 954 21 C924 18 891 26 870 39 Q863 43 865 35 Z',
].join(' ');
const caustic = [
  'M23 62 C45 82 78 88 111 77',
  'M270 75 C300 88 335 87 370 76',
  'M545 75 C574 87 618 88 653 76',
  'M860 75 C907 90 953 88 978 62',
].join(' ');

const tintColors: Record<string, string> = {
  ice: '#a9dfff',
  violet: '#b77ce8',
  teal: '#39c6bc',
  amber: '#e5a14c',
};

/** Transmit the app surface through the shell and render reflections around its glass edge. */
export function BubbleProgress({percent, colors, backdrop, finish, tint, active, material = 'gradient', size}: {
  percent: number;
  colors: string[];
  backdrop?: readonly string[];
  finish?: string;
  tint?: string;
  active: boolean;
  material?: string;
  size?: number | null;
}) {
  const id = useId().replace(/:/g, '');
  const amount = Math.min(100, Math.max(0, Number.isFinite(percent) ? percent : 0));
  const [start = '#06cfff', middle = '#315bff', end = '#b94dff'] = colors;
  const glassTint = tintColors[tint ?? 'ice'] ?? tintColors.ice;
  const tintOpacity = finish === 'clear' ? .04 : finish === 'frosted' ? .17 : .09;
  const sculpted = isLiquidMaterial(material);

  return <svg className="cg-bubble-vessel" viewBox="0 0 1000 100" preserveAspectRatio="none" aria-hidden="true">
    <defs>
      <clipPath id={`${id}outline`}><path d={vessel}/></clipPath>
      <clipPath id={`${id}fill`}><rect width={amount * 10} height="100"/></clipPath>
      <linearGradient id={`${id}tint`}>
        {[0, .5, 1].map((offset, index) => <stop key={offset} offset={offset} stopColor={backdrop?.[index] ?? glassTint} stopOpacity={tintOpacity}/>)}
      </linearGradient>
      <linearGradient id={`${id}color`}>
        <stop stopColor={start}/><stop offset=".5" stopColor={middle}/><stop offset="1" stopColor={end}/>
      </linearGradient>
      <linearGradient id={`${id}depth`} x1="0%" y1="0%" x2="0%" y2="100%">
        <stop stopColor="#b9e8ff" stopOpacity=".52"/>
        <stop offset=".18" stopColor="#91c9ef" stopOpacity=".13"/>
        <stop offset=".42" stopColor="#10233d" stopOpacity=".02"/>
        <stop offset=".68" stopColor="#090d24" stopOpacity={finish === 'recessed' ? '.29' : '.16'}/>
        <stop offset=".89" stopColor="#11b7ff" stopOpacity=".24"/>
        <stop offset="1" stopColor="#e5fcff" stopOpacity=".48"/>
      </linearGradient>
      <linearGradient id={`${id}spectrum`} x1="0%" y1="100%" x2="100%" y2="0%">
        <stop stopColor="#59f9ff"/><stop offset=".18" stopColor="#9affcd"/>
        <stop offset=".31" stopColor="#79b7ff"/><stop offset=".49" stopColor="#c69cff"/>
        <stop offset=".67" stopColor="#ff9bde"/><stop offset=".79" stopColor="#ffdaae"/>
        <stop offset=".93" stopColor="#aeceff"/><stop offset="1" stopColor="#69f5ff"/>
      </linearGradient>
      <linearGradient id={`${id}glint`} x1="0%" y1="0%" x2="0%" y2="100%">
        <stop stopColor="#fff" stopOpacity=".98"/><stop offset=".72" stopColor="#e3faff" stopOpacity=".42"/>
        <stop offset="1" stopColor="#bdf3ff" stopOpacity="0"/>
      </linearGradient>
      <linearGradient id={`${id}rim`} x1="0%" y1="0%" x2="0%" y2="100%">
        <stop stopColor="#fff" stopOpacity=".93"/><stop offset=".5" stopColor="#b7d7ff" stopOpacity=".29"/>
        <stop offset="1" stopColor="#e9fcff" stopOpacity=".76"/>
      </linearGradient>
      <radialGradient id={`${id}bubble`} cx="32%" cy="21%" r="85%">
        <stop stopColor="#fff" stopOpacity=".92"/>
        <stop offset=".28" stopColor={start} stopOpacity=".28"/>
        <stop offset=".72" stopColor={middle} stopOpacity=".13"/>
        <stop offset="1" stopColor="#fff" stopOpacity=".67"/>
      </radialGradient>
    </defs>
    <path className="cg-bubble-prism-halo" d={vessel} fill="none" stroke={`url(#${id}spectrum)`} strokeWidth="7" vectorEffect="non-scaling-stroke"/>
    <g clipPath={`url(#${id}outline)`}>
      <path d={vessel} fill={`url(#${id}tint)`}/>
      {sculpted && <foreignObject width="1000" height="100">
        <div className="cg-bubble-liquid-host"><LiquidProgress percent={amount} colors={colors} material={material} size={size} active={active}/></div>
      </foreignObject>}
      <g clipPath={`url(#${id}fill)`}>
        {!sculpted && <rect width="1000" height="100" fill={`url(#${id}color)`} fillOpacity=".84"/>}
        <path d="M0 69 C99 53 129 80 229 70 S350 58 456 70 S600 81 704 69 S852 58 1000 72 L1000 100 L0 100 Z" fill="#021c70" fillOpacity=".23"/>
        <ellipse cx="323" cy="53" rx="13" ry="12" fill={`url(#${id}bubble)`} stroke="#e8ffff" strokeOpacity=".50" vectorEffect="non-scaling-stroke"/>
        <ellipse cx="598" cy="55" rx="10" ry="10" fill={`url(#${id}bubble)`} stroke="#e8ffff" strokeOpacity=".50" vectorEffect="non-scaling-stroke"/>
      </g>
      <path d={vessel} fill={`url(#${id}depth)`}/>
      <path d={caustic} fill="none" stroke={`url(#${id}spectrum)`} strokeOpacity=".43" strokeWidth="3" vectorEffect="non-scaling-stroke"/>
      <path d={vessel} fill="none" stroke={`url(#${id}spectrum)`} strokeOpacity=".58" strokeWidth="6" vectorEffect="non-scaling-stroke"/>
      <path d={reflectedLight} fill={`url(#${id}glint)`}/>
    </g>
    <path d={vessel} fill="none" stroke={`url(#${id}rim)`} strokeWidth="1.7" vectorEffect="non-scaling-stroke"/>
  </svg>;
}
