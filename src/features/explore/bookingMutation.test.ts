import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  canSubmitBooking,
  classifyBookingTransport,
  reconcileBookingMutation,
  settleBookingMutation,
  startBookingMutation,
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
