export const SPAIN_MARKET = 'ES';

export const IDENTITY_CASE_STATES = [
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

export const OPEN_IDENTITY_CASE_STATES = [
  'SUBMITTED',
  'IN_REVIEW',
  'RESUBMITTED',
] as const;

export const FINISHED_IDENTITY_CASE_STATES = [
  'ACCEPTED',
  'REJECTED',
  'EXPIRED',
  'REVOKED',
  'SUPERSEDED',
] as const;

export const TRUST_STATUS_CODES = ['VERIFIED', 'NOT_VERIFIED'] as const;

export const SUBJECT_KINDS = ['IDENTITY', 'OWNERSHIP', 'MANAGEMENT'] as const;

export type IdentityCaseState = (typeof IDENTITY_CASE_STATES)[number];
export type TrustStatusCode = (typeof TRUST_STATUS_CODES)[number] | 'UNKNOWN';
export type SubjectKind = (typeof SUBJECT_KINDS)[number];

export type SpainIdentityStatus =
  | 'VERIFIED'
  | 'PENDING'
  | 'REJECTED'
  | 'NOT_VERIFIED'
  | 'UNAVAILABLE';

export type VerificationStatusRow = {
  subjectKind: SubjectKind;
  marketCountryCode: string | null;
  equineId: string | null;
  effectiveId: string | null;
  statusCode: TrustStatusCode;
};

export type IdentityCaseRow = {
  caseId: string;
  state: IdentityCaseState;
  marketCountryCode: string;
  outcome: string | null;
  decidedAt: string | null;
};

export type VerificationSnapshot = {
  statusRows: VerificationStatusRow[];
  identityCases: IdentityCaseRow[];
  equineNames: ReadonlyMap<string, string>;
};

export type EquineRelationView = {
  effectiveId: string;
  displayName: string;
  relationLabel: 'Propiedad' | 'Gestión';
  statusLabel: string;
};

export type SpainIdentityView = {
  marketLabel: 'España';
  status: SpainIdentityStatus;
  statusLabel: string;
  canRequest: boolean;
};
