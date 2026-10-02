import { supabase } from '../../services/supabase/client';
import { parseActivityRow } from './activityRow';
import type { ActivityBooking } from './types';

export async function listMyActivity(): Promise<ActivityBooking[]> {
  const { data, error } = await supabase.rpc('list_my_activity');

  if (error) {
    throw error;
  }

  return ((data ?? []) as unknown[]).map((row) => parseActivityRow(row));
}
