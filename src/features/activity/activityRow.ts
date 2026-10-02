import type {
  ActivityBooking,
  BookingStatus,
  CallerRelation,
  EligibilityStatus,
  SessionStatus,
} from './types';

const BOOKING_STATUSES = [
  'DRAFT',
  'REQUESTED',
  'PENDING_REQUIREMENTS',
  'PENDING_APPROVAL',
  'APPROVED',
  'CONFIRMED',
  'ACTIVE',
  'COMPLETED',
  'REJECTED',
  'CANCELLED',
  'EXPIRED',
  'DISPUTED',
] as const satisfies readonly BookingStatus[];

const ELIGIBILITY_STATUSES = [
  'ELIGIBLE',
  'ELIGIBLE_WITH_SUPERVISION',
  'REQUIRES_CENTER_ASSESSMENT',
  'REQUIRES_ZERO_SESSION',
  'REQUIRES_OWNER_APPROVAL',
  'REQUIRES_GUARDIAN_CONSENT',
  'QUALIFICATION_NOT_VERIFIED',
  'NOT_ELIGIBLE',
] as const satisfies readonly EligibilityStatus[];

const SESSION_STATUSES = [
  'READY',
  'ACTIVE',
  'ENDING',
  'COMPLETED',
  'PENDING_SYNC',
  'REQUIRES_REVIEW',
  'INVALIDATED',
] as const satisfies readonly SessionStatus[];

const UNEXPECTED_ACTIVITY_RESULT = 'Activity RPC returned an unexpected result.';

function isListed<T extends string>(values: readonly T[], value: unknown): value is T {
  return typeof value === 'string' && values.includes(value as T);
}

function isOptionalTimestamp(value: unknown): value is string | null {
  return value === null || typeof value === 'string';
}

export function parseActivityRow(value: unknown): ActivityBooking {
  if (!value || typeof value !== 'object') {
    throw new Error(UNEXPECTED_ACTIVITY_RESULT);
  }

  const row = value as Record<string, unknown>;
  const sessionId = row.session_id;
  const sessionStatus = row.session_status;
  const sessionPair =
    (sessionId === null && sessionStatus === null) ||
    (typeof sessionId === 'string' && isListed(SESSION_STATUSES, sessionStatus));

  if (
    typeof row.booking_id !== 'string' ||
    typeof row.starts_at !== 'string' ||
    typeof row.ends_at !== 'string' ||
    !isListed(BOOKING_STATUSES, row.booking_status) ||
    !(
      row.eligibility_status === null ||
      isListed(ELIGIBILITY_STATUSES, row.eligibility_status)
    ) ||
    (row.caller_relation !== 'PARTICIPANT' && row.caller_relation !== 'BOOKER') ||
    !sessionPair ||
    !isOptionalTimestamp(row.session_started_at) ||
    !isOptionalTimestamp(row.session_ended_at)
  ) {
    throw new Error(UNEXPECTED_ACTIVITY_RESULT);
  }

  return {
    bookingId: row.booking_id,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    bookingStatus: row.booking_status as BookingStatus,
    eligibilityStatus: row.eligibility_status as EligibilityStatus | null,
    callerRelation: row.caller_relation as CallerRelation,
    sessionId: sessionId as string | null,
    sessionStatus: sessionStatus as SessionStatus | null,
    sessionStartedAt: row.session_started_at,
    sessionEndedAt: row.session_ended_at,
  };
}
