import type {
  EquineManagementAssignment,
  EquineOwnership,
  EquineType,
  ManagementRole,
  OwnershipStatus,
} from './types';

const UNEXPECTED_OWNERSHIP_RESULT =
  'Equine ownership RPC returned an unexpected result.';
const UNEXPECTED_MANAGEMENT_RESULT =
  'Equine management RPC returned an unexpected result.';

function isEquineType(value: unknown): value is EquineType {
  return value === 'HORSE' || value === 'PONY';
}

function isOwnershipStatus(value: unknown): value is OwnershipStatus {
  return value === 'ACTIVE' || value === 'ENDED';
}

function asFiniteNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  return null;
}

function isManagementRole(value: unknown): value is ManagementRole {
  return (
    value === 'PRIMARY_MANAGER' ||
    value === 'CO_MANAGER' ||
    value === 'AUTHORIZED_MANAGER'
  );
}

export function isOwnershipLifecycleConsistent(
  status: unknown,
  endedAt: unknown,
): boolean {
  return (
    (status === 'ACTIVE' && endedAt === null) ||
    (status === 'ENDED' && typeof endedAt === 'string')
  );
}

function isOwnershipRow(
  value: unknown,
): value is Record<string, unknown> & { ownership_percentage: unknown } {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const row = value as Record<string, unknown>;
  return (
    typeof row.ownership_id === 'string' &&
    typeof row.equine_id === 'string' &&
    typeof row.equine_name === 'string' &&
    isEquineType(row.equine_type) &&
    row.owner_type === 'PERSON' &&
    asFiniteNumber(row.ownership_percentage) !== null &&
    isOwnershipStatus(row.status) &&
    typeof row.started_at === 'string' &&
    isOwnershipLifecycleConsistent(row.status, row.ended_at)
  );
}

function isManagementRow(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const row = value as Record<string, unknown>;
  return (
    typeof row.assignment_id === 'string' &&
    typeof row.equine_id === 'string' &&
    typeof row.equine_name === 'string' &&
    isEquineType(row.equine_type) &&
    isManagementRole(row.management_role) &&
    isOwnershipStatus(row.status) &&
    typeof row.valid_from === 'string' &&
    isOwnershipLifecycleConsistent(row.status, row.valid_until)
  );
}

export function parseEquineOwnershipRow(value: unknown): EquineOwnership {
  if (!isOwnershipRow(value)) {
    throw new Error(UNEXPECTED_OWNERSHIP_RESULT);
  }

  const percentage = asFiniteNumber(value.ownership_percentage);
  if (
    percentage === null ||
    !isEquineType(value.equine_type) ||
    !isOwnershipStatus(value.status)
  ) {
    throw new Error(UNEXPECTED_OWNERSHIP_RESULT);
  }

  return {
    ownershipId: value.ownership_id as string,
    equineId: value.equine_id as string,
    equineName: value.equine_name as string,
    equineType: value.equine_type,
    ownerType: 'PERSON',
    ownershipPercentage: percentage,
    status: value.status,
    startedAt: value.started_at as string,
    endedAt: value.ended_at as string | null,
  };
}

export function parseEquineManagementRow(
  value: unknown,
): EquineManagementAssignment {
  if (!isManagementRow(value)) {
    throw new Error(UNEXPECTED_MANAGEMENT_RESULT);
  }

  if (
    !isEquineType(value.equine_type) ||
    !isManagementRole(value.management_role) ||
    !isOwnershipStatus(value.status)
  ) {
    throw new Error(UNEXPECTED_MANAGEMENT_RESULT);
  }

  return {
    assignmentId: value.assignment_id as string,
    equineId: value.equine_id as string,
    equineName: value.equine_name as string,
    equineType: value.equine_type,
    managementRole: value.management_role,
    status: value.status,
    validFrom: value.valid_from as string,
    validUntil: value.valid_until as string | null,
  };
}
