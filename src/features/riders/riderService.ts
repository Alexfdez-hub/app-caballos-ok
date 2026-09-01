import { supabase } from '../../services/supabase/client';
import type {
  ProfileVisibility,
  RiderProfile,
  UpsertRiderProfileInput,
} from './types';

type RiderProfileRow = {
  person_id: string;
  bio: string | null;
  experience_start_year: number | null;
  profile_visibility: ProfileVisibility;
  created_at: string;
  updated_at: string;
};

function asOptionalNumber(value: unknown): number | null {
  if (value === null || value === undefined) {
    return null;
  }

  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  throw new Error('Rider profile RPC returned an unexpected result.');
}

function isProfileVisibility(
  value: unknown,
): value is RiderProfileRow['profile_visibility'] {
  return value === 'PRIVATE' || value === 'PUBLIC';
}

function mapRiderProfile(row: RiderProfileRow): RiderProfile {
  return {
    personId: row.person_id,
    bio: row.bio,
    experienceStartYear: row.experience_start_year,
    profileVisibility: row.profile_visibility,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function isRiderProfileRow(value: unknown): value is RiderProfileRow {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const row = value as Record<string, unknown>;
  return (
    typeof row.person_id === 'string' &&
    (row.bio === null || typeof row.bio === 'string') &&
    isProfileVisibility(row.profile_visibility) &&
    typeof row.created_at === 'string' &&
    typeof row.updated_at === 'string'
  );
}

function parseRiderProfileRow(value: unknown): RiderProfile {
  if (!isRiderProfileRow(value)) {
    throw new Error('Rider profile RPC returned an unexpected result.');
  }

  return mapRiderProfile({
    ...value,
    experience_start_year: asOptionalNumber(value.experience_start_year),
  });
}

export async function getMyRiderProfile(): Promise<RiderProfile | null> {
  const { data, error } = await supabase.rpc('get_my_rider_profile');

  if (error) {
    throw error;
  }

  const rows = (data ?? []) as unknown[];

  if (rows.length === 0) {
    return null;
  }

  if (rows.length !== 1) {
    throw new Error('Rider profile RPC returned an unexpected result.');
  }

  return parseRiderProfileRow(rows[0]);
}

export async function upsertMyRiderProfile(
  input: UpsertRiderProfileInput,
): Promise<RiderProfile> {
  const { data, error } = await supabase.rpc('upsert_my_rider_profile', {
    p_bio: input.bio,
    p_experience_start_year: input.experienceStartYear,
    p_profile_visibility: input.profileVisibility,
  });

  if (error) {
    throw error;
  }

  const rows = (data ?? []) as unknown[];

  if (rows.length !== 1) {
    throw new Error('Rider profile RPC returned an unexpected result.');
  }

  return parseRiderProfileRow(rows[0]);
}
