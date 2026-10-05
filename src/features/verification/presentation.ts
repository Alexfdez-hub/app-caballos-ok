import type {
  EquineRelationView,
  IdentityCaseRow,
  SpainIdentityView,
  VerificationSnapshot,
  VerificationStatusRow,
} from './types';

const SPAIN_MARKET = 'ES';
const OPEN_IDENTITY_CASE_STATES = [
  'SUBMITTED',
  'IN_REVIEW',
  'RESUBMITTED',
] as const;
const FINISHED_IDENTITY_CASE_STATES = [
  'ACCEPTED',
  'REJECTED',
  'EXPIRED',
  'REVOKED',
  'SUPERSEDED',
] as const;

export async function reloadAfterSpainIdentityRequest(actions: {
  submit: () => Promise<void>;
  load: () => Promise<VerificationSnapshot>;
}): Promise<VerificationSnapshot> {
  await actions.submit();
  return actions.load();
}

const SPAIN_IDENTITY_LABELS = {
  VERIFIED: 'Verificada',
  PENDING: 'Solicitud pendiente',
  REJECTED: 'No aceptada',
  NOT_VERIFIED: 'No verificada',
  UNAVAILABLE: 'No disponible',
} as const;

export function spainIdentityLabel(
  status: keyof typeof SPAIN_IDENTITY_LABELS,
): string {
  return SPAIN_IDENTITY_LABELS[status];
}

export function relationStatusLabel(
  statusCode: 'VERIFIED' | 'NOT_VERIFIED',
): string {
  return statusCode === 'VERIFIED' ? 'Verificada' : 'No verificada';
}

const OPEN_STATES = new Set<string>(OPEN_IDENTITY_CASE_STATES);
const FINISHED_STATES = new Set<string>(FINISHED_IDENTITY_CASE_STATES);

export function equineDisplayName(
  equineId: string,
  names: ReadonlyMap<string, string>,
): string {
  const name = names.get(equineId)?.trim() ?? '';

  if (!name || name === equineId || name.includes(equineId)) {
    return 'Equino';
  }

  return name;
}

function spainCases(cases: IdentityCaseRow[]): IdentityCaseRow[] {
  return cases.filter((row) => row.marketCountryCode === SPAIN_MARKET);
}

function spainIdentityRows(rows: VerificationStatusRow[]): VerificationStatusRow[] {
  return rows.filter(
    (row) =>
      row.subjectKind === 'IDENTITY' && row.marketCountryCode === SPAIN_MARKET,
  );
}

function latestFinishedOutcome(
  cases: IdentityCaseRow[],
): 'REJECTED' | 'OTHER' | 'UNAVAILABLE' | 'NONE' {
  const finished = cases.filter((row) => FINISHED_STATES.has(row.state));

  if (finished.length === 0) {
    return 'NONE';
  }

  const ranked = [...finished].sort((left, right) => {
    const leftTime = left.decidedAt ?? '';
    const rightTime = right.decidedAt ?? '';
    return rightTime.localeCompare(leftTime);
  });
  const latestTime = ranked[0]?.decidedAt ?? null;
  const tied = ranked.filter((row) => (row.decidedAt ?? null) === latestTime);
  const marks = new Set(
    tied.map((row) => (row.state === 'REJECTED' || row.outcome === 'REJECTED'
      ? 'REJECTED'
      : 'OTHER')),
  );

  if (marks.size !== 1) {
    return 'UNAVAILABLE';
  }

  return marks.has('REJECTED') ? 'REJECTED' : 'OTHER';
}

export function presentSpainIdentity(
  snapshot: Pick<VerificationSnapshot, 'statusRows' | 'identityCases'>,
): SpainIdentityView {
  const identityRows = spainIdentityRows(snapshot.statusRows);

  if (
    snapshot.statusRows.some((row) => row.statusCode === 'UNKNOWN') ||
    identityRows.some((row) => row.statusCode === 'UNKNOWN')
  ) {
    return {
      marketLabel: 'España',
      status: 'UNAVAILABLE',
      statusLabel: spainIdentityLabel('UNAVAILABLE'),
      canRequest: false,
    };
  }

  const verified = identityRows.some((row) => row.statusCode === 'VERIFIED');
  const notVerified = identityRows.some(
    (row) => row.statusCode === 'NOT_VERIFIED',
  );

  let status: SpainIdentityView['status'] = 'NOT_VERIFIED';

  if (verified && notVerified) {
    status = 'UNAVAILABLE';
  } else if (verified) {
    status = 'VERIFIED';
  } else if (
    spainCases(snapshot.identityCases).some((row) => OPEN_STATES.has(row.state))
  ) {
    status = 'PENDING';
  } else {
    const finished = latestFinishedOutcome(spainCases(snapshot.identityCases));
    if (finished === 'UNAVAILABLE') {
      status = 'UNAVAILABLE';
    } else if (finished === 'REJECTED') {
      status = 'REJECTED';
    }
  }

  return {
    marketLabel: 'España',
    status,
    statusLabel: spainIdentityLabel(status),
    canRequest: status === 'NOT_VERIFIED' || status === 'REJECTED',
  };
}

function relationViews(
  rows: VerificationStatusRow[],
  names: ReadonlyMap<string, string>,
  kind: 'OWNERSHIP' | 'MANAGEMENT',
): EquineRelationView[] {
  return rows
    .filter(
      (
        row,
      ): row is VerificationStatusRow & {
        statusCode: 'VERIFIED' | 'NOT_VERIFIED';
      } =>
        row.subjectKind === kind &&
        (row.statusCode === 'VERIFIED' || row.statusCode === 'NOT_VERIFIED'),
    )
    .map((row) => ({
      effectiveId: row.effectiveId ?? row.equineId ?? kind,
      displayName: equineDisplayName(row.equineId ?? '', names),
      relationLabel: kind === 'OWNERSHIP' ? 'Propiedad' : 'Gestión',
      statusLabel: relationStatusLabel(row.statusCode),
    }));
}

export function presentOwnerships(
  snapshot: VerificationSnapshot,
): EquineRelationView[] {
  return relationViews(
    snapshot.statusRows,
    snapshot.equineNames,
    'OWNERSHIP',
  );
}

export function presentManagement(
  snapshot: VerificationSnapshot,
): EquineRelationView[] {
  return relationViews(
    snapshot.statusRows,
    snapshot.equineNames,
    'MANAGEMENT',
  );
}

export function relationLabelForCode(
  statusCode: 'VERIFIED' | 'NOT_VERIFIED',
): string {
  return relationStatusLabel(statusCode);
}

export type SubmitState = {
  inFlight: boolean;
  notice: string | null;
};

export const IDENTITY_REQUEST_NOTICE =
  'Solicitud registrada. Tu identidad no queda verificada con este envío.';

export function startIdentitySubmit(state: SubmitState): SubmitState | null {
  if (state.inFlight) {
    return null;
  }

  return { inFlight: true, notice: null };
}

export function finishIdentitySubmit(state: SubmitState): SubmitState {
  return { inFlight: false, notice: state.notice };
}

export function identitySubmitSucceeded(): SubmitState {
  return { inFlight: false, notice: IDENTITY_REQUEST_NOTICE };
}
