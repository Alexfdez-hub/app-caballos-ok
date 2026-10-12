import type {
  EquineManagementAssignment,
  EquineOwnership,
} from '../equines/types';
import type { TrustStatusCode, VerificationStatusRow } from './types';

function relationTrustLabel(statusCode: TrustStatusCode): string {
  if (statusCode === 'VERIFIED') {
    return 'Verificada';
  }

  if (statusCode === 'NOT_VERIFIED') {
    return 'No verificada';
  }

  return 'No disponible';
}

export const SPAIN_MARKET = 'ES';

export const CLAIM_RECORDED_NOTICE =
  'Solicitud registrada. Esta reclamación no verifica la relación ni transfiere el equino, y no abre publicación, reservas ni pagos.';

const CLAIM_REQUEST_LABELS = {
  SUBMITTED: 'Solicitud pendiente',
  RESUBMITTED: 'Solicitud pendiente',
  IN_REVIEW: 'En revisión',
  ACCEPTED: 'Aceptada',
  REJECTED: 'No aceptada',
  UNAVAILABLE: 'No disponible',
} as const;

const OPEN_CLAIM_STATES = new Set(['SUBMITTED', 'IN_REVIEW', 'RESUBMITTED']);

export type ClaimRequestState =
  | 'SUBMITTED'
  | 'IN_REVIEW'
  | 'RESUBMITTED'
  | 'ACCEPTED'
  | 'REJECTED'
  | 'EXPIRED'
  | 'REVOKED'
  | 'SUPERSEDED'
  | 'DRAFT';

export type OwnershipClaimRecord = {
  claimId: string;
  equineId: string;
  state: ClaimRequestState;
  marketCountryCode: string;
  ownerType: string;
  ownershipPercentage: number;
  decidedAt: string | null;
};

export type ManagementClaimRecord = {
  claimId: string;
  equineId: string;
  state: ClaimRequestState;
  marketCountryCode: string;
  managerType: string;
  managementRole: string;
  decidedAt: string | null;
};

export type OwnershipClaimPayload = {
  p_equine_id: string;
  p_market_country_code: typeof SPAIN_MARKET;
  p_owner_type: 'PERSON';
  p_owner_center_id: null;
  p_ownership_percentage: number;
  p_effective_ownership_id: string;
};

export type ManagementClaimPayload = {
  p_equine_id: string;
  p_market_country_code: typeof SPAIN_MARKET;
  p_manager_type: 'PERSON';
  p_manager_center_id: null;
  p_management_role: EquineManagementAssignment['managementRole'];
  p_valid_from: string;
  p_valid_until: string | null;
  p_effective_assignment_id: string;
};

export type RelationClaimAction = {
  title: string;
  statusLabel: string | null;
  trustLabel: string;
  canSubmit: boolean;
  explanation: string | null;
  ownershipPayload: OwnershipClaimPayload | null;
  managementPayload: ManagementClaimPayload | null;
};

export type RelationClaimSection = {
  ownership: RelationClaimAction;
  management: RelationClaimAction;
};

export function claimRequestLabel(
  state: keyof typeof CLAIM_REQUEST_LABELS,
): string {
  return CLAIM_REQUEST_LABELS[state];
}

function isCurrentOwnership(row: EquineOwnership): boolean {
  return (
    row.ownerType === 'PERSON' &&
    row.status === 'ACTIVE' &&
    row.endedAt === null &&
    row.isCurrentlyEffective === true &&
    typeof row.startedAt === 'string' &&
    row.startedAt.length > 0
  );
}

function isCurrentAssignment(row: EquineManagementAssignment): boolean {
  return (
    row.status === 'ACTIVE' &&
    row.isCurrentlyEffective === true &&
    typeof row.validFrom === 'string' &&
    row.validFrom.length > 0 &&
    (row.validUntil === null || row.validUntil.length > 0)
  );
}

export function ownershipClaimPayload(
  row: EquineOwnership,
): OwnershipClaimPayload | null {
  if (!isCurrentOwnership(row)) {
    return null;
  }

  return {
    p_equine_id: row.equineId,
    p_market_country_code: SPAIN_MARKET,
    p_owner_type: 'PERSON',
    p_owner_center_id: null,
    p_ownership_percentage: row.ownershipPercentage,
    p_effective_ownership_id: row.ownershipId,
  };
}

export function managementClaimPayload(
  row: EquineManagementAssignment,
): ManagementClaimPayload | null {
  if (!isCurrentAssignment(row)) {
    return null;
  }

  return {
    p_equine_id: row.equineId,
    p_market_country_code: SPAIN_MARKET,
    p_manager_type: 'PERSON',
    p_manager_center_id: null,
    p_management_role: row.managementRole,
    p_valid_from: row.validFrom,
    p_valid_until: row.validUntil,
    p_effective_assignment_id: row.assignmentId,
  };
}

function trustLabelFor(
  rows: VerificationStatusRow[],
  equineId: string,
  kind: 'OWNERSHIP' | 'MANAGEMENT',
  effectiveId: string | null,
): { label: string; verified: boolean; unavailable: boolean } {
  const matches = rows.filter(
    (row) =>
      row.subjectKind === kind &&
      row.equineId === equineId &&
      (effectiveId === null || row.effectiveId === effectiveId),
  );

  if (matches.length !== 1) {
    return {
      label: relationTrustLabel('UNKNOWN'),
      verified: false,
      unavailable: matches.length > 1,
    };
  }

  const statusCode: TrustStatusCode = matches[0]?.statusCode ?? 'UNKNOWN';
  return {
    label: relationTrustLabel(statusCode),
    verified: statusCode === 'VERIFIED',
    unavailable: statusCode === 'UNKNOWN',
  };
}

function openClaimState(
  states: ClaimRequestState[],
): { state: ClaimRequestState } | 'AMBIGUOUS' | null {
  const open = states.filter((state) => OPEN_CLAIM_STATES.has(state));
  if (open.length === 1) {
    return { state: open[0]! };
  }
  if (open.length > 1) {
    return 'AMBIGUOUS';
  }
  return null;
}

function requestLabel(
  matched: { state: ClaimRequestState } | 'AMBIGUOUS' | null,
  trustVerified: boolean,
): { statusLabel: string | null; blocksSubmit: boolean; unavailable: boolean } {
  if (matched === 'AMBIGUOUS') {
    return {
      statusLabel: claimRequestLabel('UNAVAILABLE'),
      blocksSubmit: true,
      unavailable: true,
    };
  }

  if (matched?.state === 'SUBMITTED' || matched?.state === 'RESUBMITTED') {
    return {
      statusLabel: claimRequestLabel('SUBMITTED'),
      blocksSubmit: true,
      unavailable: false,
    };
  }

  if (matched?.state === 'IN_REVIEW') {
    return {
      statusLabel: claimRequestLabel('IN_REVIEW'),
      blocksSubmit: true,
      unavailable: false,
    };
  }

  if (trustVerified) {
    return {
      statusLabel: claimRequestLabel('ACCEPTED'),
      blocksSubmit: true,
      unavailable: false,
    };
  }

  return { statusLabel: null, blocksSubmit: false, unavailable: false };
}

function ownershipAction(
  equineId: string,
  ownerships: EquineOwnership[],
  claims: OwnershipClaimRecord[],
  trustRows: VerificationStatusRow[],
): RelationClaimAction {
  const current = ownerships.filter(
    (row) => row.equineId === equineId && isCurrentOwnership(row),
  );
  const title = 'Propiedad';

  if (current.length === 0) {
    return {
      title,
      statusLabel: null,
      trustLabel: relationTrustLabel('NOT_VERIFIED'),
      canSubmit: false,
      explanation: 'No hay una propiedad vigente que puedas reclamar.',
      ownershipPayload: null,
      managementPayload: null,
    };
  }

  if (current.length !== 1) {
    return {
      title,
      statusLabel: claimRequestLabel('UNAVAILABLE'),
      trustLabel: relationTrustLabel('UNKNOWN'),
      canSubmit: false,
      explanation: 'La reclamación de propiedad no está disponible.',
      ownershipPayload: null,
      managementPayload: null,
    };
  }

  const row = current[0]!;
  const payload = ownershipClaimPayload(row);
  const trust = trustLabelFor(trustRows, equineId, 'OWNERSHIP', row.ownershipId);
  const matched = openClaimState(
    claims
      .filter(
        (claim) =>
          claim.equineId === equineId &&
          claim.marketCountryCode === SPAIN_MARKET &&
          claim.ownerType === 'PERSON',
      )
      .map((claim) => claim.state),
  );
  const request = requestLabel(matched, trust.verified);
  const canSubmit = Boolean(
    payload &&
      payload.p_ownership_percentage === row.ownershipPercentage &&
      !trust.verified &&
      !trust.unavailable &&
      !request.blocksSubmit,
  );

  return {
    title,
    statusLabel: request.statusLabel,
    trustLabel: trust.label,
    canSubmit,
    explanation: canSubmit
      ? 'La solicitud usa la propiedad vigente de tu cuenta. No cambia el porcentaje.'
      : request.unavailable
        ? 'La reclamación de propiedad no está disponible.'
        : null,
    ownershipPayload: canSubmit ? payload : null,
    managementPayload: null,
  };
}

function managementAction(
  equineId: string,
  assignments: EquineManagementAssignment[],
  claims: ManagementClaimRecord[],
  trustRows: VerificationStatusRow[],
): RelationClaimAction {
  const current = assignments.filter(
    (row) => row.equineId === equineId && isCurrentAssignment(row),
  );
  const title = 'Responsabilidad';

  if (current.length === 0) {
    return {
      title,
      statusLabel: null,
      trustLabel: relationTrustLabel('NOT_VERIFIED'),
      canSubmit: false,
      explanation: 'No hay una responsabilidad vigente que puedas reclamar.',
      ownershipPayload: null,
      managementPayload: null,
    };
  }

  if (current.length !== 1) {
    return {
      title,
      statusLabel: claimRequestLabel('UNAVAILABLE'),
      trustLabel: relationTrustLabel('UNKNOWN'),
      canSubmit: false,
      explanation: 'La reclamación de responsabilidad no está disponible.',
      ownershipPayload: null,
      managementPayload: null,
    };
  }

  const row = current[0]!;
  const payload = managementClaimPayload(row);
  const trust = trustLabelFor(trustRows, equineId, 'MANAGEMENT', row.assignmentId);
  const matched = openClaimState(
    claims
      .filter(
        (claim) =>
          claim.equineId === equineId &&
          claim.marketCountryCode === SPAIN_MARKET &&
          claim.managerType === 'PERSON',
      )
      .map((claim) => claim.state),
  );
  const request = requestLabel(matched, trust.verified);
  const canSubmit = Boolean(
    payload &&
      payload.p_management_role === row.managementRole &&
      payload.p_valid_from === row.validFrom &&
      payload.p_valid_until === row.validUntil &&
      !trust.verified &&
      !trust.unavailable &&
      !request.blocksSubmit,
  );

  return {
    title,
    statusLabel: request.statusLabel,
    trustLabel: trust.label,
    canSubmit,
    explanation: canSubmit
      ? 'La solicitud copia el rol y las fechas de la asignación vigente.'
      : request.unavailable
        ? 'La reclamación de responsabilidad no está disponible.'
        : null,
    ownershipPayload: null,
    managementPayload: canSubmit ? payload : null,
  };
}

export function presentRelationClaims(input: {
  equineId: string;
  ownerships: EquineOwnership[];
  assignments: EquineManagementAssignment[];
  ownershipClaims: OwnershipClaimRecord[];
  managementClaims: ManagementClaimRecord[];
  trustRows: VerificationStatusRow[];
}): RelationClaimSection {
  return {
    ownership: ownershipAction(
      input.equineId,
      input.ownerships,
      input.ownershipClaims,
      input.trustRows,
    ),
    management: managementAction(
      input.equineId,
      input.assignments,
      input.managementClaims,
      input.trustRows,
    ),
  };
}
