import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { shouldApplyAccountResult } from '../explore/accountResult.ts';
import { beginExclusivePress, idleExclusivePress } from './exclusivePress.ts';
import { mountedSessionActions } from './sessionActions.ts';
import type { ActivityBooking } from './types.ts';
import {
  beginAccountRead,
  idleAccountRead,
  presentAccountSnapshot,
  retargetAccountRead,
  settleAccountRead,
  type AccountRead,
} from './accountSnapshot.ts';

const slot = {
  startsAt: '2026-12-02T10:00:00.000Z',
  endsAt: '2026-12-02T11:00:00.000Z',
};

function booking(id: string): ActivityBooking {
  return {
    bookingId: id,
    startsAt: slot.startsAt,
    endsAt: slot.endsAt,
    bookingStatus: 'CONFIRMED',
    eligibilityStatus: 'ELIGIBLE',
    callerRelation: 'PARTICIPANT',
    sessionId: null,
    sessionStatus: null,
    sessionStartedAt: null,
    sessionEndedAt: null,
  };
}

function loaded<T>(userId: string, rows: T[], requestSeq: number): AccountRead<T> {
  return {
    ownerUserId: userId,
    rows,
    errorMessage: null,
    isLoading: false,
    requestSeq,
  };
}

describe('account snapshot isolation', () => {
  it('hides account A activity while account B is still loading', () => {
    const accountA = loaded('A', [booking('a-booking')], 1);
    const pendingB = beginAccountRead(retargetAccountRead(accountA, 'B'), 'B', 3);
    const visible = presentAccountSnapshot(pendingB, 'B');
    assert.equal(visible.owned, true);
    assert.equal(visible.isLoading, true);
    assert.deepEqual(visible.rows, []);
    assert.equal(visible.errorMessage, null);
    assert.deepEqual(mountedSessionActions('upcoming', visible.rows), []);
    const poisoned = presentAccountSnapshot(
      { ...accountA, isLoading: false },
      'B',
    );
    assert.equal(poisoned.owned, false);
    assert.deepEqual(poisoned.rows, []);
  });

  it('hides account A confirm rows and their actions while B is loading', () => {
    const queueA = loaded('A', [{ bookingId: 'a-confirm' }], 1);
    const pendingB = beginAccountRead(retargetAccountRead(queueA, 'B'), 'B', 3);
    const visible = presentAccountSnapshot(pendingB, 'B');
    assert.deepEqual(visible.rows, []);
    assert.equal(visible.rows.some((row) => row.bookingId === 'a-confirm'), false);
  });

  it('drops a late account A response after the session changes', () => {
    let read = loaded('A', [booking('a-booking')], 1);
    read = {
      ...read,
      errorMessage: 'No se pudo cargar tu actividad. Inténtalo de nuevo.',
    };
    const switched = beginAccountRead(retargetAccountRead(read, 'B'), 'B', 3);
    const lateRows = settleAccountRead(switched, {
      requestSeq: 1,
      requestedUserId: 'A',
      currentUserId: 'B',
      screenActive: true,
      ok: true,
      rows: [booking('a-booking')],
      errorMessage: null,
    });
    const lateError = settleAccountRead(switched, {
      requestSeq: 1,
      requestedUserId: 'A',
      currentUserId: 'B',
      screenActive: true,
      ok: false,
      rows: [],
      errorMessage: 'permission denied for table bookings',
    });
    assert.deepEqual(presentAccountSnapshot(lateRows, 'B').rows, []);
    assert.equal(presentAccountSnapshot(lateError, 'B').errorMessage, null);
    assert.equal(lateRows.ownerUserId, 'B');
    assert.equal(lateError.ownerUserId, 'B');
  });

  it('publishes the valid account B response', () => {
    const pendingB = beginAccountRead(
      retargetAccountRead(loaded('A', [booking('a-booking')], 1), 'B'),
      'B',
      3,
    );
    const settled = settleAccountRead(pendingB, {
      requestSeq: 3,
      requestedUserId: 'B',
      currentUserId: 'B',
      screenActive: true,
      ok: true,
      rows: [booking('b-booking')],
      errorMessage: null,
    });
    const visible = presentAccountSnapshot(settled, 'B');
    assert.deepEqual(
      visible.rows.map((row) => row.bookingId),
      ['b-booking'],
    );
    assert.equal(visible.owned, true);
    assert.equal(visible.isLoading, false);
    assert.equal(
      shouldApplyAccountResult(3, 3, true, 'B', 'B'),
      true,
    );
  });

  it('keeps confirm, start, and end from launching twice', () => {
    const first = beginExclusivePress(idleExclusivePress());
    const second = beginExclusivePress(first.state);
    assert.equal(first.generation, 1);
    assert.equal(second.generation, null);
  });

  it('does not restore another account when focus returns', () => {
    const accountA = loaded('A', [booking('a-booking')], 1);
    const blurred = settleAccountRead(accountA, {
      requestSeq: 1,
      requestedUserId: 'A',
      currentUserId: 'A',
      screenActive: false,
      ok: true,
      rows: [booking('a-booking-late')],
      errorMessage: 'stale',
    });
    assert.equal(blurred, accountA);
    const switched = retargetAccountRead(blurred, 'B');
    const focusedLateA = settleAccountRead(switched, {
      requestSeq: 1,
      requestedUserId: 'A',
      currentUserId: 'B',
      screenActive: true,
      ok: true,
      rows: [booking('a-booking')],
      errorMessage: null,
    });
    assert.deepEqual(presentAccountSnapshot(focusedLateA, 'B').rows, []);
    const focusedB = settleAccountRead(
      beginAccountRead(focusedLateA, 'B', focusedLateA.requestSeq + 1),
      {
        requestSeq: focusedLateA.requestSeq + 1,
        requestedUserId: 'B',
        currentUserId: 'B',
        screenActive: true,
        ok: true,
        rows: [booking('b-booking')],
        errorMessage: null,
      },
    );
    assert.deepEqual(
      presentAccountSnapshot(focusedB, 'B').rows.map((row) => row.bookingId),
      ['b-booking'],
    );
  });

  it('covers A to null, null to B, and out-of-order responses', () => {
    const accountA = loaded('A', [booking('a-booking')], 2);
    const signedOut = retargetAccountRead(accountA, null);
    assert.deepEqual(presentAccountSnapshot(signedOut, null).rows, []);
    assert.equal(presentAccountSnapshot(signedOut, null).errorMessage, null);

    const pendingB = beginAccountRead(retargetAccountRead(signedOut, 'B'), 'B', 5);
    assert.deepEqual(presentAccountSnapshot(pendingB, 'B').rows, []);
    const earlyB = settleAccountRead(pendingB, {
      requestSeq: 5,
      requestedUserId: 'B',
      currentUserId: 'B',
      screenActive: true,
      ok: true,
      rows: [booking('b-booking')],
      errorMessage: null,
    });
    const lateA = settleAccountRead(earlyB, {
      requestSeq: 2,
      requestedUserId: 'A',
      currentUserId: 'B',
      screenActive: true,
      ok: true,
      rows: [booking('a-booking')],
      errorMessage: null,
    });
    assert.equal(lateA, earlyB);
    assert.deepEqual(
      presentAccountSnapshot(lateA, 'B').rows.map((row) => row.bookingId),
      ['b-booking'],
    );

    const backToA = beginAccountRead(retargetAccountRead(lateA, 'A'), 'A', 7);
    assert.deepEqual(presentAccountSnapshot(backToA, 'A').rows, []);
    assert.equal(idleAccountRead<ActivityBooking>('A').ownerUserId, 'A');
  });
});
