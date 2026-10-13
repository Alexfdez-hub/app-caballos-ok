import {
  listMyEquineManagementAssignments,
  listMyEquineOwnerships,
} from '../equines/ownershipService';
import { supabase } from '../../services/supabase/client';
import { VerificationResponseError } from './verificationErrors';
import { parseVerificationStatusRows } from './verificationRow';
import {
  assertSubmittedClaimResult,
  type ManagementClaimPayload,
  type ManagementClaimRecord,
  type OwnershipClaimPayload,
  type OwnershipClaimRecord,
} from './relationClaims';
import type { VerificationStatusRow } from './types';

const CLAIM_STATES = [
  'DRAFT',
  'SUBMITTED',
  'IN_REVIEW',
  'ACCEPTED',
  'REJECTED',
  'RESUBMITTED',
  'EXPIRED',
  'REVOKED',
  'SUPERSEDED',
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function requiredText(value: unknown): string {
  if (typeof value === 'string' && value.length > 0) {
    return value;
  }
  throw new VerificationResponseError();
}

function optionalTimestamp(value: unknown): string | null {
  if (value === null) {
    return null;
  }
  if (typeof value === 'string') {
    return value;
  }
  throw new VerificationResponseError();
}

function percentage(value: unknown): number {
  const parsed =
    typeof value === 'number'
      ? value
      : typeof value === 'string' && value.trim() !== ''
        ? Number(value)
        : Number.NaN;
  if (!Number.isFinite(parsed)) {
    throw new VerificationResponseError();
  }
  return parsed;
}

function claimState(value: unknown): OwnershipClaimRecord['state'] {
  if (
    typeof value === 'string' &&
    CLAIM_STATES.includes(value as (typeof CLAIM_STATES)[number])
  ) {
    return value as OwnershipClaimRecord['state'];
  }
  throw new VerificationResponseError();
}

export function parseOwnershipClaimRows(value: unknown): OwnershipClaimRecord[] {
  if (!Array.isArray(value)) {
    throw new VerificationResponseError();
  }

  return value.map((row) => {
    if (!isRecord(row)) {
      throw new VerificationResponseError();
    }
    return {
      claimId: requiredText(row.claim_id),
      equineId: requiredText(row.equine_id),
      state: claimState(row.state),
      marketCountryCode: requiredText(row.market_country_code),
      ownerType: requiredText(row.owner_type),
      ownershipPercentage: percentage(row.ownership_percentage),
      decidedAt: optionalTimestamp(row.decided_at),
    };
  });
}

export function parseManagementClaimRows(value: unknown): ManagementClaimRecord[] {
  if (!Array.isArray(value)) {
    throw new VerificationResponseError();
  }

  return value.map((row) => {
    if (!isRecord(row)) {
      throw new VerificationResponseError();
    }
    return {
      claimId: requiredText(row.claim_id),
      equineId: requiredText(row.equine_id),
      state: claimState(row.state),
      marketCountryCode: requiredText(row.market_country_code),
      managerType: requiredText(row.manager_type),
      managementRole: requiredText(row.management_role),
      decidedAt: optionalTimestamp(row.decided_at),
    };
  });
}

export type RelationClaimSnapshot = {
  ownerships: Awaited<ReturnType<typeof listMyEquineOwnerships>>;
  assignments: Awaited<ReturnType<typeof listMyEquineManagementAssignments>>;
  ownershipClaims: OwnershipClaimRecord[];
  managementClaims: ManagementClaimRecord[];
  trustRows: VerificationStatusRow[];
};

export async function loadRelationClaimSnapshot(): Promise<RelationClaimSnapshot> {
  const [ownerships, assignments, ownershipClaims, managementClaims, statusResult] =
    await Promise.all([
      listMyEquineOwnerships(),
      listMyEquineManagementAssignments(),
      supabase.rpc('list_my_equine_ownership_claims'),
      supabase.rpc('list_my_equine_management_claims'),
      supabase.rpc('list_my_verification_status'),
    ]);

  if (ownershipClaims.error || managementClaims.error || statusResult.error) {
    throw ownershipClaims.error ?? managementClaims.error ?? statusResult.error;
  }

  return {
    ownerships,
    assignments,
    ownershipClaims: parseOwnershipClaimRows(ownershipClaims.data ?? []),
    managementClaims: parseManagementClaimRows(managementClaims.data ?? []),
    trustRows: parseVerificationStatusRows(statusResult.data ?? []),
  };
}

function submittedRow(data: unknown): void {
  assertSubmittedClaimResult(data);
}

export async function submitOwnershipClaim(
  payload: OwnershipClaimPayload,
): Promise<void> {
  const { data, error } = await supabase.rpc(
    'submit_my_equine_ownership_claim',
    payload,
  );
  if (error) {
    throw error;
  }
  submittedRow(data);
}

export async function submitManagementClaim(
  payload: ManagementClaimPayload,
): Promise<void> {
  const { data, error } = await supabase.rpc(
    'submit_my_equine_management_claim',
    payload,
  );
  if (error) {
    throw error;
  }
  submittedRow(data);
}
