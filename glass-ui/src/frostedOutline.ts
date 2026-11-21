/** Outer silhouette of the rendered pane, in normalized window coordinates. */
export function frostedOutline(data:Uint8ClampedArray,width:number,height:number):number[][] {
 const left:number[][]=[],right:number[][]=[];
 for(let y=0;y<height;y++){
  let first=-1,last=-1;
  for(let x=0;x<width;x++)if((data[(y*width+x)*4+3]??0)>8){if(first<0)first=x;last=x}
  if(first>=0){left.push([first/width,y/height]);right.push([(last+1)/width,(y+1)/height])}
 }
 return left.length>1?[...left,...right.reverse()]:[];
}
