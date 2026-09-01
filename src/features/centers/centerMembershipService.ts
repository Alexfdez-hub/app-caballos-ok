import { supabase } from '../../services/supabase/client';
import { isCenterRoleCode, isMembershipStatus } from './labels';
import type { CenterMembership } from './types';

type CenterMembershipRow = {
  membership_id: string;
  center_id: string;
  center_name: string;
  role_code: string;
  status: string;
  joined_at: string;
  ended_at: string | null;
};

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
    (row.ended_at === null || typeof row.ended_at === 'string')
  );
}

function mapCenterMembership(row: CenterMembershipRow): CenterMembership {
  if (!isCenterRoleCode(row.role_code) || !isMembershipStatus(row.status)) {
    throw new Error('Center membership RPC returned an unexpected result.');
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

export async function listMyCenterMemberships(): Promise<CenterMembership[]> {
  const { data, error } = await supabase.rpc('list_my_center_memberships');

  if (error) {
    throw error;
  }

  const rows = (data ?? []) as unknown[];
  return rows.map((row) => {
    if (!isCenterMembershipRow(row)) {
      throw new Error('Center membership RPC returned an unexpected result.');
    }

    return mapCenterMembership(row);
  });
}
