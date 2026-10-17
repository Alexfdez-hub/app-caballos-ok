import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  mountedSessionActions,
  sectionMountsSessionActions,
  sessionPressPlan,
  sessionPressResult,
} from './sessionActions.ts';
import type { ActivityBooking } from './types.ts';

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

describe('activity session actions', () => {
  it('offers one start action for a confirmed booking without a session', () => {
    const booking = row();
    assert.deepEqual(mountedSessionActions('upcoming', [booking]), ['start']);
    assert.deepEqual(mountedSessionActions('agenda', [booking]), [null]);
    assert.equal(
      mountedSessionActions('upcoming', [booking]).filter((action) => action === 'start').length,
      1,
    );
  });

  it('offers one end action for an active session', () => {
    const booking = row({
      bookingStatus: 'ACTIVE',
      sessionId: 'session-1',
      sessionStatus: 'ACTIVE',
    });
    assert.deepEqual(mountedSessionActions('upcoming', [booking]), ['end']);
    assert.deepEqual(mountedSessionActions('agenda', [booking]), [null]);
  });

  it('keeps Tu agenda from mounting session actions', () => {
    assert.equal(sectionMountsSessionActions('agenda'), false);
    assert.equal(sectionMountsSessionActions('upcoming'), true);
    const rows = [
      row(),
      row({
        bookingId: 'booking-2',
        bookingStatus: 'ACTIVE',
        sessionId: 'session-2',
        sessionStatus: 'ACTIVE',
      }),
    ];
    assert.deepEqual(mountedSessionActions('agenda', rows), [null, null]);
  });

  it('ignores a second press while the single action is pending', () => {
    let pending = false;
    const first = sessionPressPlan(pending);
    if (first === 'start') {
      pending = true;
    }
    const second = sessionPressPlan(pending);
    assert.equal(first, 'start');
    assert.equal(second, 'ignore');
  });

  it('refreshes after success and keeps the error path without a second launch', () => {
    assert.equal(sessionPressResult(true), 'refresh');
    assert.equal(sessionPressResult(false), 'message');

    let pending = true;
    assert.equal(sessionPressPlan(pending), 'ignore');
    pending = false;
    assert.equal(sessionPressPlan(pending), 'start');
  });
});
