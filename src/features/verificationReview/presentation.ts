import type {
  ReviewCapability,
  ReviewDetailView,
  ReviewQueueItem,
  ReviewScreenView,
} from './types';

export const DECISION_BLOCKED_COPY =
  'La decisión queda bloqueada. Esta lectura no autoriza una aceptación ni un rechazo. Esa acción llegará solo cuando una revisión posterior compruebe la evidencia.';

export const EVIDENCE_INCOMPLETE_COPY =
  'La evidencia todavía no es suficiente para continuar.';

export const EVIDENCE_PRESENT_COPY =
  'Hay evidencia de las categorías mínimas, pero la decisión sigue bloqueada.';

export function pilotReviewIsVisible(
  capabilities: ReviewCapability[],
): boolean {
  return (
    capabilities.length === 1 &&
    capabilities[0]?.scopeType === 'MARKET' &&
    capabilities[0]?.marketCountryCode === 'ES'
  );
}

export function compareReviewQueue(
  left: ReviewQueueItem,
  right: ReviewQueueItem,
): number {
  if (left.updatedAt !== right.updatedAt) {
    return right.updatedAt < left.updatedAt ? -1 : 1;
  }

  if (left.caseType !== right.caseType) {
    return left.caseType < right.caseType ? -1 : 1;
  }

  if (left.caseId === right.caseId) {
    return 0;
  }

  return left.caseId < right.caseId ? -1 : 1;
}

export function sortReviewQueue(items: ReviewQueueItem[]): ReviewQueueItem[] {
  return [...items].sort(compareReviewQueue);
}

export function reviewActionsBlocked(
  isLoading: boolean,
  screenActive: boolean,
): boolean {
  return isLoading && screenActive;
}

export function presentReviewScreen(input: {
  hasSession: boolean;
  isLoading: boolean;
  hadAccess: boolean;
  denied: boolean;
  errorMessage: string | null;
  items: ReviewQueueItem[];
  detail: ReviewDetailView;
}): ReviewScreenView {
  if (!input.hasSession) {
    return { kind: 'signed_out' };
  }

  if (input.isLoading) {
    return { kind: 'loading' };
  }

  if (input.denied) {
    return { kind: input.hadAccess ? 'suspended' : 'unauthorized' };
  }

  if (input.errorMessage) {
    return { kind: 'error', message: input.errorMessage };
  }

  if (input.items.length === 0) {
    return { kind: 'empty' };
  }

  return {
    kind: 'queue',
    items: sortReviewQueue(input.items),
    detail: input.detail,
  };
}
