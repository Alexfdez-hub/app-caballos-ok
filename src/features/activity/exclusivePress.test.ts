import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { shouldApplyAccountResult } from '../explore/accountResult.ts';
import { userFacingMutationMessage } from './activityErrors.ts';
import {
  beginExclusivePress,
  endExclusivePress,
  idleExclusivePress,
  mayPublishExclusiveResult,
} from './exclusivePress.ts';

describe('exclusive activity press', () => {
  it('ignores a second tap while the first mutation is held', () => {
    const first = beginExclusivePress(idleExclusivePress());
    assert.equal(first.generation, 1);
    const second = beginExclusivePress(first.state);
    assert.equal(second.generation, null);
    assert.equal(second.state.generation, 1);
  });

  it('does not publish a late result after blur or an account change', () => {
    const held = beginExclusivePress(idleExclusivePress());
    assert.equal(held.generation, 1);
    assert.equal(
      mayPublishExclusiveResult(held.state, 1, false, 'account-a', 'account-a'),
      false,
    );
    assert.equal(
      mayPublishExclusiveResult(held.state, 1, true, 'account-a', 'account-b'),
      false,
    );
    assert.equal(
      mayPublishExclusiveResult(held.state, 1, true, 'account-a', 'account-a'),
      shouldApplyAccountResult(1, 1, true, 'account-a', 'account-a'),
    );
    const released = endExclusivePress(held.state, 1);
    assert.equal(
      mayPublishExclusiveResult(released, 1, true, 'account-a', 'account-a'),
      false,
    );
  });
});

describe('mutation error copy', () => {
  it('does not echo SQL or a denial detail', () => {
    assert.equal(
      userFacingMutationMessage({
        code: '42501',
        message: 'permission denied for table bookings',
      }),
      'No tienes autoridad para esta acción.',
    );
    assert.equal(
      userFacingMutationMessage(new Error('duplicate key value violates unique constraint')),
      'No se pudo completar la acción. Inténtalo de nuevo.',
    );
    assert.equal(
      userFacingMutationMessage({
        code: 'P0001',
        message: 'Only an APPROVED booking can be confirmed',
      }),
      'Solo se puede confirmar una reserva ya aprobada.',
    );
  });
});
