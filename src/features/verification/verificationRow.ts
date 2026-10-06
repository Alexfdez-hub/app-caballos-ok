import type {
  IdentityCaseRow,
  IdentityCaseState,
  SubjectKind,
  TrustStatusCode,
  VerificationStatusRow,
} from './types';

const IDENTITY_CASE_STATES = [
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
const SUBJECT_KINDS = ['IDENTITY', 'OWNERSHIP', 'MANAGEMENT'] as const;
const TRUST_STATUS_CODES = ['VERIFIED', 'NOT_VERIFIED'] as const;

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function isListed<T extends string>(
  values: readonly T[],
  value: unknown,
): value is T {
  return typeof value === 'string' && values.includes(value as T);
}

function optionalUuid(value: unknown): string | null {
  if (value === null) {
    return null;
  }

  if (typeof value === 'string' && UUID.test(value)) {
    return value;
  }

  throw new Error('Verification response could not be read.');
}

function requiredUuid(value: unknown): string {
  if (typeof value === 'string' && UUID.test(value)) {
    return value;
  }

  throw new Error('Verification response could not be read.');
}

function optionalText(value: unknown): string | null {
  if (value === null) {
    return null;
  }

  if (typeof value === 'string') {
    return value;
  }

  throw new Error('Verification response could not be read.');
}

export function parseVerificationStatusRow(
  value: unknown,
): VerificationStatusRow {
  if (!isRecord(value) || !isListed(SUBJECT_KINDS, value.subject_kind)) {
    throw new Error('Verification response could not be read.');
  }

  const subjectKind: SubjectKind = value.subject_kind;
  if (typeof value.status_code !== 'string' || value.status_code.length === 0) {
    throw new Error('Verification response could not be read.');
  }

  const statusCode: TrustStatusCode = isListed(
    TRUST_STATUS_CODES,
    value.status_code,
  )
    ? value.status_code
    : 'UNKNOWN';

  const marketCountryCode =
    value.market_country_code === null
      ? null
      : typeof value.market_country_code === 'string'
        ? value.market_country_code.trim().toUpperCase()
        : null;

  if (value.market_country_code !== null && marketCountryCode === null) {
    throw new Error('Verification response could not be read.');
  }

  const equineId = optionalUuid(value.equine_id);
  const effectiveId = optionalUuid(value.effective_id);

  if (subjectKind === 'IDENTITY') {
    if (!marketCountryCode || equineId !== null || effectiveId !== null) {
      throw new Error('Verification response could not be read.');
    }
  } else if (!equineId || !effectiveId) {
    throw new Error('Verification response could not be read.');
  }

  return {
    subjectKind,
    marketCountryCode,
    equineId,
    effectiveId,
    statusCode,
  };
}

export function parseIdentityCaseRow(value: unknown): IdentityCaseRow {
  if (!isRecord(value) || !isListed(IDENTITY_CASE_STATES, value.state)) {
    throw new Error('Verification response could not be read.');
  }

  const state: IdentityCaseState = value.state;
  const marketCountryCode =
    typeof value.market_country_code === 'string'
      ? value.market_country_code.trim().toUpperCase()
      : '';

  if (!marketCountryCode) {
    throw new Error('Verification response could not be read.');
  }

  return {
    caseId: requiredUuid(value.case_id),
    state,
    marketCountryCode,
    outcome: optionalText(value.outcome),
    decidedAt: optionalText(value.decided_at),
  };
}

export function parseVerificationStatusRows(
  value: unknown,
): VerificationStatusRow[] {
  if (!Array.isArray(value)) {
    throw new Error('Verification response could not be read.');
  }

  return value.map((row) => parseVerificationStatusRow(row));
}

export function parseIdentityCaseRows(value: unknown): IdentityCaseRow[] {
  if (!Array.isArray(value)) {
    throw new Error('Verification response could not be read.');
  }

  return value.map((row) => parseIdentityCaseRow(row));
}
