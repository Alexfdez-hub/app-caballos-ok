export type BookingMutationPhase =
  | 'idle'
  | 'pending'
  | 'ambiguous'
  | 'succeeded'
  | 'failed'
  | 'closed';

export type BookingAttempt = {
  phase: BookingMutationPhase;
  clientRequestId: string | null;
  resultStatus: string | null;
};

export type BookingOfferIdentity = {
  userId: string | null;
  equineId: string;
  centerId: string;
  serviceId: string;
  startsAt: string;
  endsAt: string;
};

const emptyAttempt = (): BookingAttempt => ({
  phase: 'idle',
  clientRequestId: null,
  resultStatus: null,
});

const bookingAttempts = new Map<string, BookingAttempt>();

export function canSubmitBooking(phase: BookingMutationPhase): boolean {
  return phase === 'idle' || phase === 'failed';
}

export function showsReconcileAction(phase: BookingMutationPhase): boolean {
  return phase === 'ambiguous';
}

export function bookingAttemptKey(identity: BookingOfferIdentity): string {
  return [
    identity.userId ?? '',
    identity.equineId,
    identity.centerId,
    identity.serviceId,
    identity.startsAt,
    identity.endsAt,
  ].join('|');
}

export function readBookingAttempt(key: string): BookingAttempt {
  return bookingAttempts.get(key) ?? emptyAttempt();
}

export function writeBookingAttempt(key: string, attempt: BookingAttempt): void {
  if (
    attempt.phase === 'idle' &&
    attempt.clientRequestId === null &&
    attempt.resultStatus === null
  ) {
    bookingAttempts.delete(key);
    return;
  }

  bookingAttempts.set(key, attempt);
}

export function startBookingMutation(
  phase: BookingMutationPhase,
): BookingMutationPhase {
  if (!canSubmitBooking(phase)) {
    return phase;
  }

  return 'pending';
}

export function settleBookingMutation(
  phase: BookingMutationPhase,
  outcome: 'ok' | 'ambiguous' | 'rejected' | 'closed',
): BookingMutationPhase {
  if (phase !== 'pending') {
    return phase;
  }

  if (outcome === 'ok') {
    return 'succeeded';
  }

  if (outcome === 'ambiguous') {
    return 'ambiguous';
  }

  if (outcome === 'closed') {
    return 'closed';
  }

  return 'failed';
}

export function reconcileBookingMutation(
  phase: BookingMutationPhase,
  serverOutcome: 'COMMITTED' | 'AMBIGUOUS' | 'ABSENT',
): BookingMutationPhase {
  if (phase !== 'ambiguous') {
    return phase;
  }

  if (serverOutcome === 'COMMITTED') {
    return 'succeeded';
  }

  if (serverOutcome === 'ABSENT') {
    return 'failed';
  }

  return 'ambiguous';
}

function errorParts(error: unknown): { code: string; message: string } {
  if (!error || typeof error !== 'object') {
    return {
      code: '',
      message: error instanceof Error ? error.message : '',
    };
  }

  const code = 'code' in error ? String((error as { code?: unknown }).code ?? '') : '';
  const message =
    'message' in error
      ? String((error as { message?: unknown }).message ?? '')
      : error instanceof Error
        ? error.message
        : '';
  return { code, message };
}

const terminalDenial =
  /Authentication required|Bookable request is not available|Identity could not be resolved|Bookable offer is not available/i;

function isTerminalBookingDenial(code: string, message: string): boolean {
  return code === '42501' || terminalDenial.test(message);
}

export function classifyBookingTransport(error: unknown): 'ambiguous' | 'rejected' | 'closed' {
  if (!error || typeof error !== 'object') {
    return 'ambiguous';
  }

  const { code, message } = errorParts(error);
  if (/Booking request outcome is ambiguous/i.test(message)) {
    return 'ambiguous';
  }

  if (isTerminalBookingDenial(code, message)) {
    return 'closed';
  }

  if (/^5\d\d$/.test(code)) {
    return 'ambiguous';
  }

  if (code.length > 0) {
    return 'rejected';
  }

  if (/client_request_id already used|invalid input/i.test(message)) {
    return 'rejected';
  }

  return 'ambiguous';
}

export function launchBookingAttempt(
  attempt: BookingAttempt,
  nextClientRequestId: string,
): { attempt: BookingAttempt; launched: boolean } {
  if (!canSubmitBooking(attempt.phase)) {
    return { attempt, launched: false };
  }

  return {
    launched: true,
    attempt: {
      phase: 'pending',
      clientRequestId: attempt.clientRequestId ?? nextClientRequestId,
      resultStatus: attempt.resultStatus,
    },
  };
}

export function acceptBookingResult(
  attempt: BookingAttempt,
  outcome: 'ok' | 'ambiguous' | 'rejected' | 'closed',
  bookingStatus: string | null,
): BookingAttempt {
  const phase = settleBookingMutation(attempt.phase, outcome);
  return {
    phase,
    clientRequestId: attempt.clientRequestId,
    resultStatus: phase === 'succeeded' ? bookingStatus : attempt.resultStatus,
  };
}

export function acceptBookingResultForSession(
  current: BookingAttempt,
  session: { userId: string | null; offerKey: string },
  incoming: {
    userId: string | null;
    offerKey: string;
    outcome: 'ok' | 'ambiguous' | 'rejected' | 'closed';
    bookingStatus: string | null;
  },
): BookingAttempt {
  if (
    incoming.userId === null ||
    incoming.userId !== session.userId ||
    incoming.offerKey !== session.offerKey
  ) {
    return current;
  }

  return acceptBookingResult(current, incoming.outcome, incoming.bookingStatus);
}

export function acceptReconcileResult(
  attempt: BookingAttempt,
  serverOutcome: 'COMMITTED' | 'AMBIGUOUS' | 'ABSENT',
  bookingStatus: string | null,
): BookingAttempt {
  const phase = reconcileBookingMutation(attempt.phase, serverOutcome);
  if (attempt.phase !== 'ambiguous') {
    return { ...attempt, phase };
  }

  if (serverOutcome === 'ABSENT') {
    return { phase, clientRequestId: null, resultStatus: null };
  }

  if (serverOutcome === 'COMMITTED') {
    return {
      phase,
      clientRequestId: attempt.clientRequestId,
      resultStatus: bookingStatus,
    };
  }

  return {
    phase,
    clientRequestId: attempt.clientRequestId,
    resultStatus: attempt.resultStatus,
  };
}

export function applyReconcileFailure(
  phase: BookingMutationPhase,
  error: unknown,
): BookingMutationPhase {
  if (phase !== 'ambiguous') {
    return phase;
  }

  const { code, message } = errorParts(error);
  if (isTerminalBookingDenial(code, message)) {
    return 'closed';
  }

  return 'ambiguous';
}
