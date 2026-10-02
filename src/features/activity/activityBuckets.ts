import type { ActivityBooking, ActivityBucket } from './types';

const OPEN_REQUEST_STATUSES = new Set([
  'DRAFT',
  'REQUESTED',
  'PENDING_REQUIREMENTS',
  'PENDING_APPROVAL',
  'APPROVED',
]);

export function activityBucket(
  row: ActivityBooking,
  now: Date,
): ActivityBucket | null {
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

export function groupActivity(rows: ActivityBooking[], now: Date) {
  const upcoming: ActivityBooking[] = [];
  const openRequests: ActivityBooking[] = [];
  const history: ActivityBooking[] = [];

  for (const row of rows) {
    const bucket = activityBucket(row, now);
    if (bucket === 'upcoming') {
      upcoming.push(row);
    } else if (bucket === 'open_request') {
      openRequests.push(row);
    } else if (bucket === 'history') {
      history.push(row);
    }
  }

  return { upcoming, openRequests, history };
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
