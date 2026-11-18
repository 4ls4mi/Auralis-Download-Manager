/** Convert a recorded percentage to a safe drawing value. */
export function sculptedPercent(value: number | null | undefined): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.min(100, value)) : 0;
}
/** Disconnected links fill in order; parallel paths show the same progress. */
export function sculptedPartPercent(value: number, count: number, index: number, sequential: boolean): number {
  const percent = sculptedPercent(value);
  if (!sequential) return percent;
  return sculptedPercent(percent * count - index * 100);
}
/** Pausing colors the whole track red. Loss keeps known progress over red. */
export function sculptedConnectionState(percent: number | null, paused: boolean, lost: boolean) {
  return {percent: paused ? 0 : sculptedPercent(percent), red: paused || lost};
}
