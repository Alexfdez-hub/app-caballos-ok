import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  acceptBookingResult,
  acceptBookingResultForSession,
  acceptReconcileResult,
  applyReconcileFailure,
  bookingAttemptKey,
  canSubmitBooking,
  classifyBookingTransport,
  launchBookingAttempt,
  readBookingAttempt,
  reconcileBookingMutation,
  settleBookingMutation,
  showsReconcileAction,
  startBookingMutation,
  writeBookingAttempt,
  type BookingAttempt,
} from './bookingMutation.ts';
import { shouldApplyAccountResult } from './accountResult.ts';
import { initialExploreRange, shiftExploreRange } from './exploreRange.ts';
import { formatOfferRange } from './formatOfferRange.ts';
import { parseBookableOffer } from './offerRow.ts';

describe('booking mutation', () => {
  it('ignores a second tap while a request is pending', () => {
    const pending = startBookingMutation('idle');
    assert.equal(pending, 'pending');
    assert.equal(startBookingMutation(pending), 'pending');
    assert.equal(canSubmitBooking(pending), false);
  });

  it('keeps an ambiguous timeout ambiguous until the server is read', () => {
    const pending = startBookingMutation('idle');
    const ambiguous = settleBookingMutation(pending, 'ambiguous');
    assert.equal(ambiguous, 'ambiguous');
    assert.equal(canSubmitBooking(ambiguous), false);
    assert.equal(startBookingMutation(ambiguous), 'ambiguous');
    assert.equal(reconcileBookingMutation(ambiguous, 'AMBIGUOUS'), 'ambiguous');
    assert.equal(reconcileBookingMutation(ambiguous, 'COMMITTED'), 'succeeded');
    assert.equal(reconcileBookingMutation(ambiguous, 'ABSENT'), 'failed');
  });

  it('does not turn a late success into a result after the phase left pending', () => {
    const ambiguous = settleBookingMutation('pending', 'ambiguous');
    assert.equal(settleBookingMutation(ambiguous, 'ok'), 'ambiguous');
  });

  it('classifies a transport failure without a database code as ambiguous', () => {
    assert.equal(classifyBookingTransport(new TypeError('Network request failed')), 'ambiguous');
    assert.equal(
      classifyBookingTransport({ code: '42501', message: 'Bookable offer is not available' }),
      'rejected',
    );
    assert.equal(
      classifyBookingTransport({ message: 'Bookable request is not available' }),
      'rejected',
    );
  });
});

describe('ambiguous P0001 booking request', () => {
  const ambiguousError = {
    code: 'P0001',
    message: 'Booking request outcome is ambiguous',
  };
  const offer = {
    equineId: 'equine-1',
    centerId: 'center-1',
    serviceId: 'service-1',
    startsAt: '2026-12-02T09:00:00.000Z',
    endsAt: '2026-12-02T10:00:00.000Z',
  };

  function ambiguousAttempt(): BookingAttempt {
    const launched = launchBookingAttempt(
      { phase: 'idle', clientRequestId: null, resultStatus: null },
      'client-request-1',
    );
    return acceptBookingResult(
      launched.attempt,
      classifyBookingTransport(ambiguousError),
      null,
    );
  }

  it('keeps the request blocked and shows reconcile after P0001', () => {
    const attempt = ambiguousAttempt();
    assert.equal(attempt.phase, 'ambiguous');
    assert.equal(canSubmitBooking(attempt.phase), false);
    assert.equal(showsReconcileAction(attempt.phase), true);
    assert.equal(attempt.clientRequestId, 'client-request-1');
  });

  it('does not launch another mutation and reuses the same client request id', () => {
    const attempt = ambiguousAttempt();
    const second = launchBookingAttempt(attempt, 'client-request-2');
    const third = launchBookingAttempt(second.attempt, 'client-request-3');
    assert.equal(second.launched, false);
    assert.equal(third.launched, false);
    assert.equal(second.attempt.clientRequestId, 'client-request-1');
    assert.equal(third.attempt.clientRequestId, 'client-request-1');
    assert.equal(canSubmitBooking(third.attempt.phase), false);
  });

  it('closes on COMMITTED and keeps the block while AMBIGUOUS', () => {
    const attempt = ambiguousAttempt();
    const committed = acceptReconcileResult(attempt, 'COMMITTED', 'APPROVED');
    assert.equal(committed.phase, 'succeeded');
    assert.equal(committed.resultStatus, 'APPROVED');
    assert.equal(committed.clientRequestId, 'client-request-1');
    assert.equal(canSubmitBooking(committed.phase), false);
    assert.equal(showsReconcileAction(committed.phase), false);

    const stillAmbiguous = acceptReconcileResult(attempt, 'AMBIGUOUS', null);
    assert.equal(stillAmbiguous.phase, 'ambiguous');
    assert.equal(stillAmbiguous.clientRequestId, 'client-request-1');
    assert.equal(canSubmitBooking(stillAmbiguous.phase), false);
    assert.equal(showsReconcileAction(stillAmbiguous.phase), true);
  });

  it('keeps an absent key on the existing failed path', () => {
    const attempt = ambiguousAttempt();
    const absent = acceptReconcileResult(attempt, 'ABSENT', null);
    assert.equal(absent.phase, 'failed');
    assert.equal(absent.clientRequestId, null);
    assert.equal(canSubmitBooking(absent.phase), true);
  });

  it('keeps a recoverable reconcile error ambiguous and closes 42501', () => {
    const attempt = ambiguousAttempt();
    assert.equal(
      applyReconcileFailure(attempt.phase, new TypeError('Network request failed')),
      'ambiguous',
    );
    assert.equal(
      applyReconcileFailure(attempt.phase, { code: '503', message: 'upstream unavailable' }),
      'ambiguous',
    );
    assert.equal(attempt.clientRequestId, 'client-request-1');
    assert.equal(canSubmitBooking(attempt.phase), false);

    const closed = applyReconcileFailure(attempt.phase, {
      code: '42501',
      message: 'Bookable request is not available',
    });
    assert.equal(closed, 'closed');
    assert.equal(canSubmitBooking(closed), false);
    assert.equal(showsReconcileAction(closed), false);
  });

  it('does not let another account or offer inherit the ambiguous key', () => {
    const keyA = bookingAttemptKey({ userId: 'user-a', ...offer });
    const keyB = bookingAttemptKey({ userId: 'user-b', ...offer });
    const otherOffer = bookingAttemptKey({ ...offer, userId: 'user-a', equineId: 'equine-2' });
    writeBookingAttempt(keyA, ambiguousAttempt());

    assert.equal(readBookingAttempt(keyB).phase, 'idle');
    assert.equal(readBookingAttempt(keyB).clientRequestId, null);
    assert.equal(readBookingAttempt(otherOffer).phase, 'idle');
    assert.equal(readBookingAttempt(otherOffer).clientRequestId, null);
    assert.equal(readBookingAttempt(keyA).clientRequestId, 'client-request-1');
  });

  it('ignores a late result from another account, offer, or an earlier phase', () => {
    const current = ambiguousAttempt();
    const otherAccount = acceptBookingResultForSession(
      current,
      { userId: 'user-a', offerKey: 'offer-a' },
      { userId: 'user-b', offerKey: 'offer-a', outcome: 'ok', bookingStatus: 'APPROVED' },
    );
    const otherOffer = acceptBookingResultForSession(
      current,
      { userId: 'user-a', offerKey: 'offer-a' },
      { userId: 'user-a', offerKey: 'offer-b', outcome: 'ok', bookingStatus: 'APPROVED' },
    );
    const lateSameSession = acceptBookingResultForSession(
      current,
      { userId: 'user-a', offerKey: 'offer-a' },
      { userId: 'user-a', offerKey: 'offer-a', outcome: 'ok', bookingStatus: 'APPROVED' },
    );

    assert.equal(otherAccount.phase, 'ambiguous');
    assert.equal(otherAccount.clientRequestId, 'client-request-1');
    assert.equal(otherOffer.clientRequestId, 'client-request-1');
    assert.equal(lateSameSession.phase, 'ambiguous');
    assert.equal(lateSameSession.resultStatus, null);
    assert.equal(
      shouldApplyAccountResult(4, 4, true, 'user-a', 'user-b'),
      false,
    );
  });

  it('does not let a refresh started before the mutation clear the ambiguous key', () => {
    const attempt = ambiguousAttempt();
    const refreshApplies = shouldApplyAccountResult(1, 2, true, 'user-a', 'user-a');
    assert.equal(refreshApplies, false);
    assert.equal(attempt.phase, 'ambiguous');
    assert.equal(attempt.clientRequestId, 'client-request-1');
    assert.equal(canSubmitBooking(attempt.phase), false);
  });
});

describe('account isolation', () => {
  it('drops a late response from the previous account', () => {
    assert.equal(shouldApplyAccountResult(1, 1, true, 'user-a', 'user-a'), true);
    assert.equal(shouldApplyAccountResult(1, 1, true, 'user-a', 'user-b'), false);
    assert.equal(shouldApplyAccountResult(1, 2, true, 'user-b', 'user-b'), false);
    assert.equal(shouldApplyAccountResult(1, 1, false, 'user-a', 'user-a'), false);
    assert.equal(shouldApplyAccountResult(1, 1, true, null, null), false);
  });
});

describe('explore range', () => {
  it('pages seven UTC days without exceeding the read bound', () => {
    const range = initialExploreRange(new Date('2026-10-16T15:00:00.000Z'));
    assert.equal(range.start, '2026-10-16T00:00:00.000Z');
    assert.equal(range.end, '2026-10-23T00:00:00.000Z');
    const next = shiftExploreRange(range, 7);
    assert.equal(next.start, '2026-10-23T00:00:00.000Z');
    assert.equal(next.end, '2026-10-30T00:00:00.000Z');
  });
});

describe('offer presentation', () => {
  it('formats a slot in the center time zone and falls back to UTC', () => {
    assert.equal(
      formatOfferRange(
        '2026-12-02T09:00:00.000Z',
        '2026-12-02T10:00:00.000Z',
        'Europe/Madrid',
      ),
      '2026-12-02 10:00–11:00 Europe/Madrid',
    );
    assert.equal(
      formatOfferRange('2026-12-02T09:00:00.000Z', '2026-12-02T10:00:00.000Z', 'Not/AZone'),
      '2026-12-02 09:00–10:00 UTC',
    );
  });

  it('keeps a null duration limit null', () => {
    const offer = parseBookableOffer({
      center_id: 'center',
      center_name: 'TEST_ONLY Vertical Center',
      center_timezone: 'Europe/Madrid',
      equine_id: 'equine',
      equine_name: 'TEST_ONLY Equine',
      service_id: 'service',
      service_name: 'TEST_ONLY Session',
      service_type: 'EQUINE_SESSION',
      starts_at: '2026-12-02T09:00:00.000Z',
      ends_at: '2026-12-02T10:00:00.000Z',
      default_duration_minutes: 60,
      duration_limit_minutes: null,
    });
    assert.equal(offer.durationLimitMinutes, null);
    assert.equal(offer.defaultDurationMinutes, 60);
  });
});
