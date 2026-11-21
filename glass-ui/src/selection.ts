/** Select within the current visible order; IDs outside the view are kept only when toggling. */
export function selectDownload(visible:number[], current:number[], anchor:number|null, id:number, shift:boolean, toggle:boolean):number[] {
  if (shift && anchor!==null) {
    const a=visible.indexOf(anchor), b=visible.indexOf(id);
    if(a>=0 && b>=0) {
      const range=visible.slice(Math.min(a,b),Math.max(a,b)+1);
      return toggle ? Array.from(new Set([...current,...range])) : range;
    }
  }
  if(toggle) return current.includes(id)?current.filter(x=>x!==id):[...current,id];
  return [id];
}
