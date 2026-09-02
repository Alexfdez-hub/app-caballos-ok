import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  isCenterMembershipLifecycleConsistent,
  parseCenterMembershipRow,
} from './centerMembershipRow.ts';

const unexpectedResult = /Center membership RPC returned an unexpected result/;

function rpcRow(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    membership_id: 'membership-1',
    center_id: 'center-1',
    center_name: 'Alpha',
    role_code: 'ADMIN',
    status: 'ACTIVE',
    joined_at: '2026-01-01T00:00:00.000Z',
    ended_at: null,
    ...overrides,
  };
}

describe('center membership RPC lifecycle payloads', () => {
  it('accepts ACTIVE with ended_at null', () => {
    assert.equal(
      isCenterMembershipLifecycleConsistent('ACTIVE', null),
      true,
    );

    const membership = parseCenterMembershipRow(rpcRow());
    assert.equal(membership.status, 'ACTIVE');
    assert.equal(membership.endedAt, null);
  });

  it('accepts ENDED with ended_at string', () => {
    assert.equal(
      isCenterMembershipLifecycleConsistent(
        'ENDED',
        '2026-02-01T00:00:00.000Z',
      ),
      true,
    );

    const membership = parseCenterMembershipRow(
      rpcRow({
        status: 'ENDED',
        ended_at: '2026-02-01T00:00:00.000Z',
      }),
    );
    assert.equal(membership.status, 'ENDED');
    assert.equal(membership.endedAt, '2026-02-01T00:00:00.000Z');
  });

  it('fails closed for ACTIVE with ended_at string', () => {
    assert.equal(
      isCenterMembershipLifecycleConsistent(
        'ACTIVE',
        '2026-02-01T00:00:00.000Z',
      ),
      false,
    );

    assert.throws(
      () =>
        parseCenterMembershipRow(
          rpcRow({
            status: 'ACTIVE',
            ended_at: '2026-02-01T00:00:00.000Z',
          }),
        ),
      unexpectedResult,
    );
  });

  it('fails closed for ENDED with ended_at null', () => {
    assert.equal(
      isCenterMembershipLifecycleConsistent('ENDED', null),
      false,
    );

    assert.throws(
      () =>
        parseCenterMembershipRow(
          rpcRow({
            status: 'ENDED',
            ended_at: null,
          }),
        ),
      unexpectedResult,
    );
  });
});
