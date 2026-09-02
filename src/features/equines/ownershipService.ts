import { supabase } from '../../services/supabase/client';
import {
  parseEquineManagementRow,
  parseEquineOwnershipRow,
} from './ownershipRow';
import type { EquineManagementAssignment, EquineOwnership } from './types';

export async function listMyEquineOwnerships(): Promise<EquineOwnership[]> {
  const { data, error } = await supabase.rpc('list_my_equine_ownerships');

  if (error) {
    throw error;
  }

  return ((data ?? []) as unknown[]).map((row) => parseEquineOwnershipRow(row));
}

export async function listMyEquineManagementAssignments(): Promise<
  EquineManagementAssignment[]
> {
  const { data, error } = await supabase.rpc(
    'list_my_equine_management_assignments',
  );

  if (error) {
    throw error;
  }

  return ((data ?? []) as unknown[]).map((row) => parseEquineManagementRow(row));
}
