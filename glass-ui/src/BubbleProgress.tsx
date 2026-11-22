import {useId} from 'react';
import {isLiquidMaterial, LiquidProgress} from './LiquidIndicators';

const vessel = 'M4 50 C4 15 24 3 49 7 C86 11 98 33 132 33 C169 33 181 12 215 13 C253 14 268 35 304 34 C341 33 357 8 395 8 C435 8 450 33 486 32 C523 31 536 15 573 17 C611 19 627 33 663 33 C700 33 715 16 752 16 C789 16 806 34 841 33 C878 32 892 7 931 7 C971 7 996 18 996 50 C996 82 971 93 931 93 C892 93 878 68 841 67 C806 66 789 84 752 84 C715 84 700 67 663 67 C627 67 611 81 573 83 C536 85 523 69 486 68 C450 67 435 92 395 92 C357 92 341 67 304 66 C268 65 253 86 215 87 C181 88 169 67 132 67 C98 67 86 89 49 93 C24 97 4 85 4 50 Z';
const reflectedLight = 'M21 37 C30 19 54 15 80 27 C56 23 39 26 26 39 Q20 44 21 37 Z M171 35 C186 21 214 16 239 25 C214 23 194 28 175 37 Q169 41 171 35 Z M347 36 C364 18 392 12 419 21 C395 20 374 27 351 39 Q345 42 347 36 Z M532 36 C550 24 572 20 598 30 C574 28 557 30 536 39 Q530 42 532 36 Z M716 38 C734 24 756 21 778 29 C757 28 738 33 720 40 Q714 43 716 38 Z M886 39 C906 18 938 12 963 22 C942 20 918 27 891 41 Q884 45 886 39 Z';
const caustic = 'M20 62 C48 91 77 82 104 73 S153 64 173 76 S225 91 258 74 S305 66 333 78 S387 91 424 74 S467 65 503 78 S553 89 591 75 S636 66 671 78 S727 90 763 75 S803 65 837 77 S890 88 919 75 S959 65 978 57';

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
        <path d="M0 72 C75 51 111 85 185 72 S300 57 372 72 S484 88 557 70 S668 56 740 73 S860 87 940 67 L1000 78 L1000 100 L0 100 Z" fill="#021c70" fillOpacity=".23"/>
        <ellipse cx="240" cy="51" rx="12" ry="15" fill={`url(#${id}bubble)`} stroke="#e8ffff" strokeOpacity=".50" vectorEffect="non-scaling-stroke"/>
        <ellipse cx="520" cy="56" rx="9" ry="12" fill={`url(#${id}bubble)`} stroke="#e8ffff" strokeOpacity=".50" vectorEffect="non-scaling-stroke"/>
      </g>
      <path d={vessel} fill={`url(#${id}depth)`}/>
      <path d={caustic} fill="none" stroke={`url(#${id}spectrum)`} strokeOpacity=".43" strokeWidth="3" vectorEffect="non-scaling-stroke"/>
      <path d={vessel} fill="none" stroke={`url(#${id}spectrum)`} strokeOpacity=".58" strokeWidth="6" vectorEffect="non-scaling-stroke"/>
      <path d={reflectedLight} fill={`url(#${id}glint)`}/>
    </g>
    <path d={vessel} fill="none" stroke={`url(#${id}rim)`} strokeWidth="1.7" vectorEffect="non-scaling-stroke"/>
  </svg>;
}
