import { supabase } from '../../services/supabase/client';
import {
  mapIdentityMarkets,
  mapIdentityRows,
} from './identityMarket';
import type { CompleteIdentityInput, Identity, IdentityMarket } from './types';

export async function ensureMyIdentity(): Promise<Identity> {
  const { data, error } = await supabase.rpc('ensure_my_identity');

  if (error) {
    throw error;
  }

  return mapIdentityRows(data);
}

export async function completeMyIdentity(
  input: CompleteIdentityInput,
): Promise<Identity> {
  const { data, error } = await supabase.rpc('complete_my_identity', {
    p_first_name: input.firstName,
    p_last_name: input.lastName,
    p_date_of_birth: input.dateOfBirth,
    p_country_code: input.countryCode,
  });

  if (error) {
    throw error;
  }

  return mapIdentityRows(data);
}

export async function listIdentityMarkets(): Promise<IdentityMarket[]> {
  const { data, error } = await supabase.rpc('list_identity_markets');

  if (error) {
    throw error;
  }

  return mapIdentityMarkets(data);
}
