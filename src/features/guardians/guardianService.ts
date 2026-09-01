import { supabase } from '../../services/supabase/client';
import type { GuardianConsent, GuardianRelationship } from './types';

type RelationshipRow = {
  id: string;
  minor_person_id: string;
  minor_first_name: string | null;
  minor_last_name: string | null;
  relationship_type: string;
  verification_status: GuardianRelationship['verificationStatus'];
  verified_at: string | null;
  expires_at: string | null;
  revoked_at: string | null;
};

type ConsentRow = {
  id: string;
  guardian_relationship_id: string;
  minor_person_id: string;
  consent_type: string;
  scope_type: string;
  terms_version: string;
  status: GuardianConsent['status'];
  granted_at: string;
  expires_at: string | null;
  revoked_at: string | null;
};

function mapRelationship(row: RelationshipRow): GuardianRelationship {
  return {
    id: row.id,
    minorPersonId: row.minor_person_id,
    minorFirstName: row.minor_first_name,
    minorLastName: row.minor_last_name,
    relationshipType: row.relationship_type,
    verificationStatus: row.verification_status,
    verifiedAt: row.verified_at,
    expiresAt: row.expires_at,
    revokedAt: row.revoked_at,
  };
}

function mapConsent(row: ConsentRow): GuardianConsent {
  return {
    id: row.id,
    guardianRelationshipId: row.guardian_relationship_id,
    minorPersonId: row.minor_person_id,
    consentType: row.consent_type,
    scopeType: row.scope_type,
    termsVersion: row.terms_version,
    status: row.status,
    grantedAt: row.granted_at,
    expiresAt: row.expires_at,
    revokedAt: row.revoked_at,
  };
}

export async function listMyGuardianRelationships(): Promise<
  GuardianRelationship[]
> {
  const { data, error } = await supabase.rpc('list_my_guardian_relationships');

  if (error) {
    throw error;
  }

  return ((data ?? []) as RelationshipRow[]).map(mapRelationship);
}

export async function listMyGuardianConsents(): Promise<GuardianConsent[]> {
  const { data, error } = await supabase.rpc('list_my_guardian_consents');

  if (error) {
    throw error;
  }

  return ((data ?? []) as ConsentRow[]).map(mapConsent);
}

export async function grantGuardianConsent(input: {
  relationshipId: string;
  marketCode: string;
}): Promise<void> {
  const { error } = await supabase.rpc('grant_guardian_consent', {
    p_guardian_relationship_id: input.relationshipId,
    p_consent_type: 'EQUESTRIAN_ACTIVITY',
    p_scope_type: 'GENERAL',
    p_terms_version: 'mvp0-guardian-consent-1',
    p_market_code: input.marketCode,
    p_expires_at: null,
  });

  if (error) {
    throw error;
  }
}

export async function revokeGuardianConsent(consentId: string): Promise<void> {
  const { error } = await supabase.rpc('revoke_guardian_consent', {
    p_consent_id: consentId,
  });

  if (error) {
    throw error;
  }
}

export async function hasAcceptedGuardianPolicy(
  marketCode: string,
): Promise<boolean> {
  const { data, error } = await supabase.rpc('has_accepted_required_policy', {
    p_policy_type: 'GUARDIAN_POLICY',
    p_market_code: marketCode,
  });

  if (error) {
    throw error;
  }

  return data === true;
}
