import type { ActivityBooking } from './types';

export type ActivitySectionId = 'upcoming' | 'agenda';

export type SessionActionKind = 'start' | 'end';

export function sectionMountsSessionActions(section: ActivitySectionId): boolean {
  return section === 'upcoming';
}

export function sessionActionForRow(row: ActivityBooking): SessionActionKind | null {
  if (row.bookingStatus === 'CONFIRMED' && !row.sessionId) {
    return 'start';
  }
  if (row.sessionStatus === 'ACTIVE' && row.sessionId) {
    return 'end';
  }
  return null;
}

export function mountedSessionActions(
  section: ActivitySectionId,
  rows: ActivityBooking[],
): Array<SessionActionKind | null> {
  if (!sectionMountsSessionActions(section)) {
    return rows.map(() => null);
  }
  return rows.map((row) => sessionActionForRow(row));
}

export function sessionPressPlan(pending: boolean): 'ignore' | 'start' {
  return pending ? 'ignore' : 'start';
}

export function sessionPressResult(succeeded: boolean): 'refresh' | 'message' {
  return succeeded ? 'refresh' : 'message';
}
