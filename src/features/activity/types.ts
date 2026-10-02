export type BookingStatus =
  | 'DRAFT'
  | 'REQUESTED'
  | 'PENDING_REQUIREMENTS'
  | 'PENDING_APPROVAL'
  | 'APPROVED'
  | 'CONFIRMED'
  | 'ACTIVE'
  | 'COMPLETED'
  | 'REJECTED'
  | 'CANCELLED'
  | 'EXPIRED'
  | 'DISPUTED';

export type EligibilityStatus =
  | 'ELIGIBLE'
  | 'ELIGIBLE_WITH_SUPERVISION'
  | 'REQUIRES_CENTER_ASSESSMENT'
  | 'REQUIRES_ZERO_SESSION'
  | 'REQUIRES_OWNER_APPROVAL'
  | 'REQUIRES_GUARDIAN_CONSENT'
  | 'QUALIFICATION_NOT_VERIFIED'
  | 'NOT_ELIGIBLE';

export type SessionStatus =
  | 'READY'
  | 'ACTIVE'
  | 'ENDING'
  | 'COMPLETED'
  | 'PENDING_SYNC'
  | 'REQUIRES_REVIEW'
  | 'INVALIDATED';
export type CallerRelation = 'PARTICIPANT' | 'BOOKER';
export type ActivityBucket = 'upcoming' | 'open_request' | 'history';

export type ActivityBooking = {
  bookingId: string;
  startsAt: string;
  endsAt: string;
  bookingStatus: BookingStatus;
  eligibilityStatus: EligibilityStatus | null;
  callerRelation: CallerRelation;
  sessionId: string | null;
  sessionStatus: SessionStatus | null;
  sessionStartedAt: string | null;
  sessionEndedAt: string | null;
};
