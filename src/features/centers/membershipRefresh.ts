export function shouldApplyCenterMembershipRefresh(
  requestSeq: number,
  latestSeq: number,
  isScreenActive: boolean,
): boolean {
  return isScreenActive && requestSeq === latestSeq;
}
