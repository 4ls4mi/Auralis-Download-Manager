/** Explicit, local-only desktop capture lifecycle. It must be armed with a
 * native guard that excludes every application window, including future ones.
 * This module never persists, transmits, or requests audio from capture frames. */
export interface CaptureGuard {
  arm(): Promise<void>;
  disarm(): Promise<void>;
}
export type DisplayPicker = (options:DisplayMediaStreamOptions)=>Promise<MediaStream>;
export class DesktopCapture {
 private state:'idle'|'arming'|'armed'|'selecting'|'active'|'stopping'='idle';
 private stream:MediaStream|null=null;
 private cleanup:Promise<void>|null=null;
 private pendingArm:Promise<void>|null=null;
 private pendingPicker:Promise<MediaStream>|null=null;
 constructor(private guard:CaptureGuard,private onEnded:()=>void=()=>{}){}
 get status(){return this.state}
 // Invoke before presenting the Start button. The native guard must reject
 // unless exclusion is installed and maintained for all app windows.
 async arm(){
  if(this.state!=='idle')throw Error('Desktop capture is already in use');
  this.state='arming';
  this.pendingArm=this.guard.arm();
  try{await this.pendingArm;if(this.state!=='arming')throw Error('Desktop capture was cancelled');this.state='armed'}catch(e){if(this.state==='arming')this.state='idle';throw e}finally{this.pendingArm=null}
 }
 // Call directly from a user click: browsers require transient user activation
 // for the OS picker, so there must be no asynchronous work before picker().
 async startFromClick(picker:DisplayPicker):Promise<MediaStream>{
  if(this.state!=='armed')throw Error('Desktop capture protection is not armed');
  this.state='selecting';
  try{
   this.pendingPicker=picker({video:{displaySurface:'monitor'},audio:false});
   const stream=await this.pendingPicker;this.pendingPicker=null;
   if(this.state!=='selecting'){stream.getTracks().forEach(t=>t.stop());throw Error('Desktop capture was cancelled')}
   this.stream=stream;
   const video=stream.getVideoTracks();
   if(video.length!==1||video[0].getSettings().displaySurface!=='monitor')throw Error('Select a whole display for the glass backdrop');
   video[0].addEventListener('ended',this.handleEnded,{once:true});
   this.state='active';return stream;
  }catch(e){this.pendingPicker=null;await this.stop();throw e}
 }
 private handleEnded=()=>{void this.stop().finally(()=>this.onEnded())};
 stop():Promise<void>{
  if(this.cleanup)return this.cleanup;
  if(this.state==='idle')return Promise.resolve();
  this.state='stopping';
  const pendingArm=this.pendingArm, pendingPicker=this.pendingPicker;
  if(this.stream){for(const track of this.stream.getTracks()){track.removeEventListener('ended',this.handleEnded);track.stop()}this.stream=null}
  this.cleanup=(async()=>{if(pendingArm){try{await pendingArm}catch{return}}if(pendingPicker){try{const stream=await pendingPicker;stream.getTracks().forEach(t=>t.stop())}catch{/* The picker was cancelled. */}}await this.guard.disarm()})().finally(()=>{this.state='idle';this.cleanup=null});return this.cleanup;
 }
}
/** Convert a window rectangle in physical desktop pixels to capture pixels.
 * Rejects spanning or unmapped windows rather than sampling unrelated content. */
export function mapCaptureRect(monitor:{x:number;y:number;width:number;height:number},window:{x:number;y:number;width:number;height:number},capture:{width:number;height:number}){
 const values=[monitor.x,monitor.y,monitor.width,monitor.height,window.x,window.y,window.width,window.height,capture.width,capture.height];
 if(!values.every(Number.isFinite)||monitor.width<=0||monitor.height<=0||capture.width<=0||capture.height<=0||window.width<=0||window.height<=0)throw Error('Invalid desktop coordinates');
 const x=window.x-monitor.x,y=window.y-monitor.y;
 if(x<0||y<0||x+window.width>monitor.width||y+window.height>monitor.height)throw Error('Window is outside the selected display');
 return {x:x*capture.width/monitor.width,y:y*capture.height/monitor.height,width:window.width*capture.width/monitor.width,height:window.height*capture.height/monitor.height};
}
