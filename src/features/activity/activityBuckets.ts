import type { ActivityBooking, ActivityBucket } from './types';

const OPEN_REQUEST_STATUSES = new Set([
  'DRAFT',
  'REQUESTED',
  'PENDING_REQUIREMENTS',
  'PENDING_APPROVAL',
  'APPROVED',
]);

const CLOSED_STATUSES = new Set([
  'CANCELLED',
  'REJECTED',
  'EXPIRED',
  'DISPUTED',
]);

export function activityBucket(
  row: ActivityBooking,
  now: Date,
): ActivityBucket | null {
  if (CLOSED_STATUSES.has(row.bookingStatus)) {
    return 'closed';
  }

  if (row.bookingStatus === 'COMPLETED' || row.sessionStatus === 'COMPLETED') {
    return 'history';
  }

  if (row.bookingStatus === 'ACTIVE') {
    return 'upcoming';
  }

  if (
    row.bookingStatus === 'CONFIRMED' &&
    new Date(row.endsAt).getTime() > now.getTime()
  ) {
    return 'upcoming';
  }

  if (OPEN_REQUEST_STATUSES.has(row.bookingStatus)) {
    return 'open_request';
  }

  return null;
}

export type HomeActivitySummary = {
  next: ActivityBooking | null;
  openRequestCount: number;
};

export type HomePanelKind = 'loading' | 'error' | 'next' | 'empty' | 'open';

export function homeActivityPanels(
  settled: boolean,
  errorMessage: string | null,
  summary: HomeActivitySummary,
): { next: HomePanelKind; pending: HomePanelKind } {
  if (!settled) {
    return { next: 'loading', pending: 'loading' };
  }

  if (errorMessage) {
    return { next: 'error', pending: 'error' };
  }

  return {
    next: summary.next ? 'next' : 'empty',
    pending: summary.openRequestCount > 0 ? 'open' : 'empty',
  };
}

export function summarizeHomeActivity(
  rows: ActivityBooking[],
  now: Date,
): HomeActivitySummary {
  const grouped = groupActivity(rows, now);
  const next =
    [...grouped.upcoming].sort((left, right) => {
      const byStart =
        new Date(left.startsAt).getTime() - new Date(right.startsAt).getTime();
      if (byStart !== 0) {
        return byStart;
      }
      return left.bookingId.localeCompare(right.bookingId);
    })[0] ?? null;

  return {
    next,
    openRequestCount: grouped.openRequests.length,
  };
}

export function groupActivity(rows: ActivityBooking[], now: Date) {
  const upcoming: ActivityBooking[] = [];
  const openRequests: ActivityBooking[] = [];
  const history: ActivityBooking[] = [];
  const closed: ActivityBooking[] = [];

  for (const row of rows) {
    const bucket = activityBucket(row, now);
    if (bucket === 'upcoming') {
      upcoming.push(row);
    } else if (bucket === 'open_request') {
      openRequests.push(row);
    } else if (bucket === 'history') {
      history.push(row);
    } else if (bucket === 'closed') {
      closed.push(row);
    }
  }

  return { upcoming, openRequests, history, closed };
}

export function formatActivityRange(startsAt: string, endsAt: string): string {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  const pad = (value: number) => String(value).padStart(2, '0');
  const date = `${start.getUTCFullYear()}-${pad(start.getUTCMonth() + 1)}-${pad(start.getUTCDate())}`;
  const startTime = `${pad(start.getUTCHours())}:${pad(start.getUTCMinutes())}`;
  const endTime = `${pad(end.getUTCHours())}:${pad(end.getUTCMinutes())}`;
  return `${date} ${startTime}–${endTime} UTC`;
}
