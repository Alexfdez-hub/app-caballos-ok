import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  centerRoleLabel,
  groupMembershipsByCenter,
  isCenterRoleCode,
  isMembershipStatus,
  membershipStatusLabel,
} from './labels.ts';
import type { CenterMembership } from './types.ts';

function membership(
  overrides: Partial<CenterMembership> &
    Pick<CenterMembership, 'membershipId' | 'centerId' | 'centerName' | 'roleCode'>,
): CenterMembership {
  return {
    status: 'ACTIVE',
    joinedAt: '2026-01-01T00:00:00.000Z',
    endedAt: null,
    ...overrides,
  };
}

describe('center membership labels', () => {
  it('accepts only frozen MVP0 Center role codes', () => {
    assert.equal(isCenterRoleCode('ADMIN'), true);
    assert.equal(isCenterRoleCode('MANAGER'), true);
    assert.equal(isCenterRoleCode('INSTRUCTOR'), true);
    assert.equal(isCenterRoleCode('ASSESSOR'), true);
    assert.equal(isCenterRoleCode('OWNER'), false);
    assert.equal(isCenterRoleCode('admin'), false);
  });

  it('accepts only foundation membership statuses', () => {
    assert.equal(isMembershipStatus('ACTIVE'), true);
    assert.equal(isMembershipStatus('ENDED'), true);
    assert.equal(isMembershipStatus('INVITED'), false);
    assert.equal(isMembershipStatus('SUSPENDED'), false);
  });

  it('maps internal role codes to UI labels without treating them as global roles', () => {
    assert.equal(centerRoleLabel('ADMIN'), 'Administrador');
    assert.equal(centerRoleLabel('ASSESSOR'), 'Evaluador');
  });

  it('maps membership status to UI labels', () => {
    assert.equal(membershipStatusLabel('ACTIVE'), 'Activa');
    assert.equal(membershipStatusLabel('ENDED'), 'Finalizada');
  });

  it('groups memberships by Center and keeps active Centers first', () => {
    const grouped = groupMembershipsByCenter([
      membership({
        membershipId: '1',
        centerId: 'beta',
        centerName: 'Beta',
        roleCode: 'ASSESSOR',
        status: 'ENDED',
        endedAt: '2026-02-01T00:00:00.000Z',
      }),
      membership({
        membershipId: '2',
        centerId: 'alpha',
        centerName: 'Alpha',
        roleCode: 'ADMIN',
      }),
      membership({
        membershipId: '3',
        centerId: 'alpha',
        centerName: 'Alpha',
        roleCode: 'INSTRUCTOR',
      }),
    ]);

    assert.equal(grouped.length, 2);
    assert.equal(grouped[0]?.centerName, 'Alpha');
    assert.equal(grouped[0]?.memberships.length, 2);
    assert.equal(grouped[1]?.centerName, 'Beta');
  });
});
