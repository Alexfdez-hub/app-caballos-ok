export type BookingMutationPhase =
  | 'idle'
  | 'pending'
  | 'ambiguous'
  | 'succeeded'
  | 'failed';

export function canSubmitBooking(phase: BookingMutationPhase): boolean {
  return phase === 'idle' || phase === 'failed';
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
  outcome: 'ok' | 'ambiguous' | 'rejected',
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

export function classifyBookingTransport(error: unknown): 'ambiguous' | 'rejected' {
  if (!error || typeof error !== 'object') {
    return 'ambiguous';
  }

  const code = 'code' in error ? String((error as { code?: unknown }).code ?? '') : '';
  if (code.length > 0) {
    return 'rejected';
  }

  const message =
    'message' in error
      ? String((error as { message?: unknown }).message ?? '')
      : error instanceof Error
        ? error.message
        : '';

  if (
    /Authentication required|Bookable request is not available|Identity could not be resolved|Bookable offer is not available|client_request_id already used|Booking request outcome is ambiguous|invalid input/i.test(
      message,
    )
  ) {
    return 'rejected';
  }

  return 'ambiguous';
}
