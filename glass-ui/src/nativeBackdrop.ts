/** Blur samples the desktop behind the square native client area. */
export function nativeBackdrop(mode: string, surfaceStyle: string): 'blur' | 'acrylic' | null {
  if (mode !== 'desktop') return null;
  if (surfaceStyle === 'soft') return 'blur';
  if (surfaceStyle === 'frosted' || surfaceStyle === 'tinted') return 'acrylic';
  return null;
}
