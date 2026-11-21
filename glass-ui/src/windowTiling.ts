/** Identify Windows-style snap layouts using physical work-area coordinates. */
export function isTiledWindow(pos:{x:number;y:number},size:{width:number;height:number},work:{position:{x:number;y:number};size:{width:number;height:number}}):boolean {
 const {x,y}=work.position,{width:w,height:h}=work.size;
 if(w<=0||h<=0||size.width<=0||size.height<=0)return false;
 const tolerance=16;
 const near=(a:number,b:number)=>Math.abs(a-b)<=tolerance;
 const left=near(pos.x,x),right=near(pos.x+size.width,x+w),top=near(pos.y,y),bottom=near(pos.y+size.height,y+h);
 const fraction=(value:number,total:number)=>[1/3,1/2,2/3,1].some(n=>near(value,total*n));
 return (left||right)&&(top||bottom)&&fraction(size.width,w)&&fraction(size.height,h)&&(size.width<w-tolerance||size.height<h-tolerance);
}
