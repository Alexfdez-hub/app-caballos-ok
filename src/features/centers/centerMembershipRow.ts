import { isCenterRoleCode, isMembershipStatus } from './labels';
import type { CenterMembership } from './types';

const UNEXPECTED_MEMBERSHIP_RESULT =
  'Center membership RPC returned an unexpected result.';

type CenterMembershipRow = {
  membership_id: string;
  center_id: string;
  center_name: string;
  role_code: string;
  status: string;
  joined_at: string;
  ended_at: string | null;
};

export function isCenterMembershipLifecycleConsistent(
  status: unknown,
  endedAt: unknown,
): boolean {
  return (
    (status === 'ACTIVE' && endedAt === null) ||
    (status === 'ENDED' && typeof endedAt === 'string')
  );
}

function isCenterMembershipRow(value: unknown): value is CenterMembershipRow {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const row = value as Record<string, unknown>;
  return (
    typeof row.membership_id === 'string' &&
    typeof row.center_id === 'string' &&
    typeof row.center_name === 'string' &&
    isCenterRoleCode(row.role_code) &&
    isMembershipStatus(row.status) &&
    typeof row.joined_at === 'string' &&
    isCenterMembershipLifecycleConsistent(row.status, row.ended_at)
  );
}

function mapCenterMembership(row: CenterMembershipRow): CenterMembership {
  if (
    !isCenterRoleCode(row.role_code) ||
    !isMembershipStatus(row.status) ||
    !isCenterMembershipLifecycleConsistent(row.status, row.ended_at)
  ) {
    throw new Error(UNEXPECTED_MEMBERSHIP_RESULT);
  }

  return {
    membershipId: row.membership_id,
    centerId: row.center_id,
    centerName: row.center_name,
    roleCode: row.role_code,
    status: row.status,
    joinedAt: row.joined_at,
    endedAt: row.ended_at,
  };
}

export function parseCenterMembershipRow(value: unknown): CenterMembership {
  if (!isCenterMembershipRow(value)) {
    throw new Error(UNEXPECTED_MEMBERSHIP_RESULT);
  }

  return mapCenterMembership(value);
}
