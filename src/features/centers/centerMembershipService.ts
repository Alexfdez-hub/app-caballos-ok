import { supabase } from '../../services/supabase/client';
import { parseCenterMembershipRow } from './centerMembershipRow';
import type { CenterMembership } from './types';

export async function listMyCenterMemberships(): Promise<CenterMembership[]> {
  const { data, error } = await supabase.rpc('list_my_center_memberships');

  if (error) {
    throw error;
  }

  const rows = (data ?? []) as unknown[];
  return rows.map((row) => parseCenterMembershipRow(row));
}
