import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  isOwnershipLifecycleConsistent,
  parseEquineManagementRow,
  parseEquineOwnershipRow,
} from './ownershipRow.ts';
import { effectiveRelationStatusLabel } from './labels.ts';

function ownershipRpc(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    ownership_id: 'own-1',
    equine_id: 'eq-1',
    equine_name: 'Pilot',
    equine_type: 'HORSE',
    owner_type: 'PERSON',
    ownership_percentage: 60,
    status: 'ACTIVE',
    is_currently_effective: true,
    started_at: '2026-01-01T00:00:00.000Z',
    ended_at: null,
    ...overrides,
  };
}

function managementRpc(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    assignment_id: 'asg-1',
    equine_id: 'eq-1',
    equine_name: 'Pilot',
    equine_type: 'HORSE',
    management_role: 'PRIMARY_MANAGER',
    status: 'ACTIVE',
    is_currently_effective: true,
    valid_from: '2026-01-01T00:00:00.000Z',
    valid_until: null,
    ...overrides,
  };
}

describe('equine ownership RPC lifecycle payloads', () => {
  it('accepts ACTIVE with ended_at null', () => {
    assert.equal(isOwnershipLifecycleConsistent('ACTIVE', null), true);
    const row = parseEquineOwnershipRow(ownershipRpc());
    assert.equal(row.status, 'ACTIVE');
    assert.equal(row.isCurrentlyEffective, true);
    assert.equal(row.endedAt, null);
  });

  it('fails closed for ACTIVE with ended_at string', () => {
    assert.throws(
      () =>
        parseEquineOwnershipRow(
          ownershipRpc({
            status: 'ACTIVE',
            ended_at: '2026-02-01T00:00:00.000Z',
          }),
        ),
      /unexpected result/,
    );
  });

  it('accepts numeric percentage encoded as a string', () => {
    const row = parseEquineOwnershipRow(
      ownershipRpc({ ownership_percentage: '60' }),
    );
    assert.equal(row.ownershipPercentage, 60);
  });

  it('fails closed for CENTER owner_type from the person RPC', () => {
    assert.throws(
      () => parseEquineOwnershipRow(ownershipRpc({ owner_type: 'CENTER' })),
      /unexpected result/,
    );
  });

  it('keeps stored ACTIVE while marking a future-dated row as not currently effective', () => {
    const row = parseEquineOwnershipRow(
      ownershipRpc({ is_currently_effective: false }),
    );
    assert.equal(row.status, 'ACTIVE');
    assert.equal(row.isCurrentlyEffective, false);
    assert.equal(
      effectiveRelationStatusLabel(row.status, row.isCurrentlyEffective),
      'Aún no vigente',
    );
  });

  it('fails closed when the derived effective flag is missing', () => {
    const payload = ownershipRpc();
    delete payload.is_currently_effective;
    assert.throws(() => parseEquineOwnershipRow(payload), /unexpected result/);
  });
});

describe('equine management RPC lifecycle payloads', () => {
  it('accepts PRIMARY_MANAGER ACTIVE', () => {
    const row = parseEquineManagementRow(managementRpc());
    assert.equal(row.managementRole, 'PRIMARY_MANAGER');
    assert.equal(row.validUntil, null);
    assert.equal(row.isCurrentlyEffective, true);
  });

  it('does not display a future stored-ACTIVE assignment as currently effective', () => {
    const row = parseEquineManagementRow(
      managementRpc({ is_currently_effective: false }),
    );
    assert.equal(row.status, 'ACTIVE');
    assert.equal(row.isCurrentlyEffective, false);
    assert.equal(
      effectiveRelationStatusLabel(row.status, row.isCurrentlyEffective),
      'Aún no vigente',
    );
  });

  it('fails closed for ENDED with valid_until null', () => {
    assert.throws(
      () =>
        parseEquineManagementRow(
          managementRpc({
            status: 'ENDED',
            valid_until: null,
          }),
        ),
      /unexpected result/,
    );
  });
});
