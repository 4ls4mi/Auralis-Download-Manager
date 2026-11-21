/** Native backdrops cover the HWND rectangle, even when a shader draws an
 * irregular shape inside it. Keep the floating frosted outline transparent. */
export function nativeBackdrop(mode:string, material:string, surfaceStyle:string, flat:boolean):'blur'|'acrylic'|null {
 if(mode!=='desktop'||(material==='frosted-water-351'&&!flat))return null;
 if(surfaceStyle==='soft')return 'blur';
 if(surfaceStyle==='frosted'||surfaceStyle==='tinted')return 'acrylic';
 return null;
}
