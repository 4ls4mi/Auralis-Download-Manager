export type FrostedResizeDirection = 'North'|'South'|'East'|'West'|'NorthEast'|'NorthWest'|'SouthEast'|'SouthWest';
/** Find an outward-facing edge in the pane's alpha mask. Coordinates/radius
 * are in CSS pixels, so the target tracks the rendered outline at any scale. */
export function frostedResizeDirection(data:Uint8ClampedArray,width:number,height:number,cssWidth:number,cssHeight:number,x:number,y:number,radius=12):FrostedResizeDirection|null{
 if(!width||!height||!cssWidth||!cssHeight||x<0||y<0||x>=cssWidth||y>=cssHeight)return null;
 const sample=(px:number,py:number)=>{const ix=Math.floor(px/cssWidth*width),iy=Math.floor(py/cssHeight*height);return ix<0||iy<0||ix>=width||iy>=height?0:data[(iy*width+ix)*4+3]??0};
 const left=sample(x-radius,y),right=sample(x+radius,y),top=sample(x,y-radius),bottom=sample(x,y+radius);
 const west=left<20&&right>60,east=right<20&&left>60,north=top<20&&bottom>60,south=bottom<20&&top>60;
 if(north&&west)return 'NorthWest';if(north&&east)return 'NorthEast';if(south&&west)return 'SouthWest';if(south&&east)return 'SouthEast';
 if(west)return 'West';if(east)return 'East';if(north)return 'North';if(south)return 'South';
 const diagonals:[number,number,FrostedResizeDirection][]=[[-1,-1,'NorthWest'],[1,-1,'NorthEast'],[-1,1,'SouthWest'],[1,1,'SouthEast']];
 for(const [dx,dy,direction] of diagonals)if(sample(x+dx*radius,y+dy*radius)<20&&sample(x-dx*radius,y-dy*radius)>60)return direction;
 return null;
}
