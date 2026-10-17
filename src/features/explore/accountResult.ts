export function shouldApplyAccountResult(
  requestSeq: number,
  latestSeq: number,
  isScreenActive: boolean,
  requestedUserId: string | null,
  currentUserId: string | null,
): boolean {
  return (
    isScreenActive &&
    requestSeq === latestSeq &&
    requestedUserId !== null &&
    requestedUserId === currentUserId
  );
}
