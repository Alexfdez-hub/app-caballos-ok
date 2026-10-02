import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { activityBucket, formatActivityRange, groupActivity } from './activityBuckets.ts';
import { userFacingActivityMessage } from './activityErrors.ts';
import { parseActivityRow } from './activityRow.ts';
import type { ActivityBooking } from './types.ts';

const now = new Date('2026-10-02T12:00:00.000Z');

function row(overrides: Partial<ActivityBooking> = {}): ActivityBooking {
  return {
    bookingId: 'booking-1',
    startsAt: '2026-12-01T10:00:00.000Z',
    endsAt: '2026-12-01T11:00:00.000Z',
    bookingStatus: 'CONFIRMED',
    eligibilityStatus: 'ELIGIBLE',
    callerRelation: 'PARTICIPANT',
    sessionId: null,
    sessionStatus: null,
    sessionStartedAt: null,
    sessionEndedAt: null,
    ...overrides,
  };
}

describe('activity buckets', () => {
  it('keeps a future confirmed booking upcoming', () => {
    assert.equal(activityBucket(row(), now), 'upcoming');
  });

  it('hides a confirmed booking whose window has already ended', () => {
    assert.equal(
      activityBucket(
        row({
          startsAt: '2026-10-01T10:00:00.000Z',
          endsAt: '2026-10-01T11:00:00.000Z',
        }),
        now,
      ),
      null,
    );
  });

  it('treats an active booking as upcoming and an approved request as open', () => {
    assert.equal(activityBucket(row({ bookingStatus: 'ACTIVE' }), now), 'upcoming');
    assert.equal(
      activityBucket(row({ bookingStatus: 'APPROVED' }), now),
      'open_request',
    );
    assert.equal(
      activityBucket(row({ bookingStatus: 'PENDING_REQUIREMENTS' }), now),
      'open_request',
    );
  });

  it('puts a completed booking or session in history', () => {
    assert.equal(activityBucket(row({ bookingStatus: 'COMPLETED' }), now), 'history');
    assert.equal(
      activityBucket(
        row({
          bookingStatus: 'ACTIVE',
          sessionId: 'session-1',
          sessionStatus: 'COMPLETED',
        }),
        now,
      ),
      'history',
    );
  });

  it('does not surface cancelled or rejected rows', () => {
    const grouped = groupActivity(
      [
        row({ bookingId: 'open', bookingStatus: 'REQUESTED' }),
        row({ bookingId: 'next', bookingStatus: 'CONFIRMED' }),
        row({ bookingId: 'done', bookingStatus: 'COMPLETED' }),
        row({ bookingId: 'gone', bookingStatus: 'CANCELLED' }),
      ],
      now,
    );
    assert.deepEqual(
      grouped.openRequests.map((item) => item.bookingId),
      ['open'],
    );
    assert.deepEqual(
      grouped.upcoming.map((item) => item.bookingId),
      ['next'],
    );
    assert.deepEqual(
      grouped.history.map((item) => item.bookingId),
      ['done'],
    );
  });

  it('formats the range in UTC', () => {
    assert.equal(
      formatActivityRange('2026-12-01T10:00:00.000Z', '2026-12-01T11:30:00.000Z'),
      '2026-12-01 10:00–11:30 UTC',
    );
  });
});

describe('activity RPC parsing', () => {
  it('accepts a personal row without a session', () => {
    const parsed = parseActivityRow({
      booking_id: 'booking-1',
      starts_at: '2026-12-01T10:00:00.000Z',
      ends_at: '2026-12-01T11:00:00.000Z',
      booking_status: 'APPROVED',
      eligibility_status: 'ELIGIBLE',
      caller_relation: 'BOOKER',
      session_id: null,
      session_status: null,
      session_started_at: null,
      session_ended_at: null,
    });
    assert.equal(parsed.callerRelation, 'BOOKER');
    assert.equal(parsed.sessionId, null);
  });

  it('fails closed when a session id arrives without a status', () => {
    assert.throws(
      () =>
        parseActivityRow({
          booking_id: 'booking-1',
          starts_at: '2026-12-01T10:00:00.000Z',
          ends_at: '2026-12-01T11:00:00.000Z',
          booking_status: 'CONFIRMED',
          eligibility_status: null,
          caller_relation: 'PARTICIPANT',
          session_id: 'session-1',
          session_status: null,
          session_started_at: null,
          session_ended_at: null,
        }),
      /unexpected result/,
    );
  });
});

describe('activity error copy', () => {
  it('does not echo a database error', () => {
    assert.equal(
      userFacingActivityMessage(new Error('permission denied for table bookings')),
      'No se pudo cargar tu actividad. Inténtalo de nuevo.',
    );
  });
});
