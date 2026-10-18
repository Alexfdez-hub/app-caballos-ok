import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';

import { activityBucket, groupActivity } from '../activity/activityBuckets.ts';
import { mountedSessionActions } from '../activity/sessionActions.ts';
import type { ActivityBooking } from '../activity/types.ts';
import { shouldApplyAccountResult } from './accountResult.ts';
import {
  acceptBookingResult,
  acceptReconcileResult,
  canSubmitBooking,
  classifyBookingTransport,
  launchBookingAttempt,
  showsReconcileAction,
  type BookingAttempt,
} from './bookingMutation.ts';
import { parseBookableOffer, parseConfirmableBooking } from './offerRow.ts';

const slot = {
  startsAt: '2026-12-02T10:00:00.000Z',
  endsAt: '2026-12-02T11:00:00.000Z',
};

function activityRow(overrides: Partial<ActivityBooking>): ActivityBooking {
  return {
    bookingId: 'booking-1',
    startsAt: slot.startsAt,
    endsAt: slot.endsAt,
    bookingStatus: 'APPROVED',
    eligibilityStatus: 'ELIGIBLE',
    callerRelation: 'BOOKER',
    sessionId: null,
    sessionStatus: null,
    sessionStartedAt: null,
    sessionEndedAt: null,
    ...overrides,
  };
}

describe('vertical offer detail', () => {
  it('keeps owner and private fields off the parsed offer and confirm row', () => {
    const offer = parseBookableOffer({
      center_id: 'center-1',
      center_name: 'Center',
      center_timezone: 'Europe/Madrid',
      equine_id: 'equine-1',
      equine_name: 'Equine',
      service_id: 'service-1',
      service_name: 'Session',
      service_type: 'EQUINE_SESSION',
      starts_at: slot.startsAt,
      ends_at: slot.endsAt,
      default_duration_minutes: 60,
      duration_limit_minutes: null,
      owner_name: 'hidden',
    });
    assert.equal('owner_name' in offer, false);
    assert.deepEqual(Object.keys(offer).sort(), [
      'centerId',
      'centerName',
      'centerTimezone',
      'defaultDurationMinutes',
      'durationLimitMinutes',
      'endsAt',
      'equineId',
      'equineName',
      'serviceId',
      'serviceName',
      'serviceType',
      'startsAt',
    ]);

    const confirmable = parseConfirmableBooking({
      booking_id: 'booking-1',
      equine_name: 'Equine',
      center_name: 'Center',
      service_name: 'Session',
      starts_at: slot.startsAt,
      ends_at: slot.endsAt,
      booking_status: 'APPROVED',
      participant_person_id: 'person-1',
    });
    assert.equal('participant_person_id' in confirmable, false);
  });
});

describe('vertical request and activity', () => {
  it('requests once, reconciles an ambiguous result, then shows it as an open request', () => {
    let attempt: BookingAttempt = {
      phase: 'idle',
      clientRequestId: null,
      resultStatus: null,
    };
    const first = launchBookingAttempt(attempt, 'key-1');
    attempt = first.attempt;
    const second = launchBookingAttempt(attempt, 'key-2');
    assert.equal(first.launched, true);
    assert.equal(second.launched, false);
    assert.equal(second.attempt.clientRequestId, 'key-1');

    attempt = acceptBookingResult(
      attempt,
      classifyBookingTransport({ code: '503', message: 'upstream timeout' }),
      null,
    );
    assert.equal(attempt.phase, 'ambiguous');
    assert.equal(canSubmitBooking(attempt.phase), false);
    assert.equal(showsReconcileAction(attempt.phase), true);

    attempt = acceptReconcileResult(attempt, 'COMMITTED', 'APPROVED');
    assert.equal(attempt.phase, 'succeeded');
    assert.equal(attempt.resultStatus, 'APPROVED');

    const grouped = groupActivity(
      [activityRow({ bookingStatus: 'APPROVED' })],
      new Date('2026-12-01T00:00:00.000Z'),
    );
    assert.equal(grouped.openRequests.length, 1);
    assert.equal(grouped.upcoming.length, 0);
    assert.deepEqual(mountedSessionActions('upcoming', grouped.upcoming), []);
  });

  it('keeps another account out of the requester activity and the confirm queue', () => {
    assert.equal(shouldApplyAccountResult(1, 1, true, 'account-a', 'account-b'), false);
    const own = groupActivity(
      [activityRow({ bookingId: 'own', bookingStatus: 'CONFIRMED' })],
      new Date('2026-12-01T00:00:00.000Z'),
    );
    const foreign = groupActivity([], new Date('2026-12-01T00:00:00.000Z'));
    assert.equal(own.upcoming.length, 1);
    assert.equal(foreign.upcoming.length, 0);
    assert.equal(foreign.openRequests.length, 0);
  });

  it('moves a confirmed booking through start and end into history', () => {
    const now = new Date('2026-12-01T00:00:00.000Z');
    const confirmed = activityRow({ bookingStatus: 'CONFIRMED', sessionId: null });
    assert.equal(activityBucket(confirmed, now), 'upcoming');
    assert.deepEqual(mountedSessionActions('upcoming', [confirmed]), ['start']);
    assert.deepEqual(mountedSessionActions('agenda', [confirmed]), [null]);

    const active = activityRow({
      bookingStatus: 'ACTIVE',
      sessionId: 'session-1',
      sessionStatus: 'ACTIVE',
    });
    assert.deepEqual(mountedSessionActions('upcoming', [active]), ['end']);

    const completed = activityRow({
      bookingStatus: 'COMPLETED',
      sessionId: 'session-1',
      sessionStatus: 'COMPLETED',
    });
    assert.equal(activityBucket(completed, now), 'history');
    assert.deepEqual(mountedSessionActions('upcoming', [completed]), [null]);
  });
});

describe('remote smoke runbook', () => {
  const runbook = readFileSync('docs/VERTICAL_REMOTE_SMOKE.md', 'utf8');
  const preflight = runbook.split('```sql')[1]?.split('```')[0] ?? '';

  it('keeps the preflight read-only and free of stored identities', () => {
    assert.match(preflight, /begin transaction read only/i);
    assert.match(preflight, /rollback/i);
    assert.doesNotMatch(preflight, /\b(insert|update|delete|merge)\b/i);
    assert.doesNotMatch(preflight, /vertical_fixture_install/);
    assert.doesNotMatch(preflight, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
    assert.doesNotMatch(preflight, /@/);
    assert.match(runbook, /vertical_fixture_install/);
    assert.match(runbook, /no se ejecuta/i);
  });
});
