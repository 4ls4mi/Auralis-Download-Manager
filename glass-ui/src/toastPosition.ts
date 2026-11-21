/** Keep the popup above the usual Windows notification area. Coordinates and
 * dimensions are physical pixels; spacing is specified in logical pixels. */
export function updateToastPosition(area:{position:{x:number;y:number};size:{width:number;height:number}},size:{width:number;height:number},scaleFactor:number){
 const scale=Number.isFinite(scaleFactor)&&scaleFactor>0?scaleFactor:1;
 const margin=Math.round(16*scale),reserve=Math.round(260*scale);
 return {x:Math.max(area.position.x,area.position.x+area.size.width-size.width-margin),y:Math.max(area.position.y,area.position.y+area.size.height-size.height-margin-reserve)};
}
