import { supabase } from '../../services/supabase/client';
import type { CompleteIdentityInput, Identity } from './types';

type IdentityRow = {
  user_account_id: string;
  person_id: string;
  first_name: string | null;
  last_name: string | null;
  date_of_birth: string | null;
  is_complete: boolean;
};

function mapIdentity(row: IdentityRow): Identity {
  return {
    userAccountId: row.user_account_id,
    personId: row.person_id,
    firstName: row.first_name,
    lastName: row.last_name,
    dateOfBirth: row.date_of_birth,
    isComplete: row.is_complete,
  };
}

function requireIdentityRow(data: unknown): IdentityRow {
  if (!Array.isArray(data) || data.length !== 1) {
    throw new Error('Identity RPC returned an unexpected result.');
  }

  return data[0] as IdentityRow;
}

export async function ensureMyIdentity(): Promise<Identity> {
  const { data, error } = await supabase.rpc('ensure_my_identity');

  if (error) {
    throw error;
  }

  return mapIdentity(requireIdentityRow(data));
}

export async function completeMyIdentity(
  input: CompleteIdentityInput,
): Promise<Identity> {
  const { data, error } = await supabase.rpc('complete_my_identity', {
    p_first_name: input.firstName,
    p_last_name: input.lastName,
    p_date_of_birth: input.dateOfBirth,
  });

  if (error) {
    throw error;
  }

  return mapIdentity(requireIdentityRow(data));
}
