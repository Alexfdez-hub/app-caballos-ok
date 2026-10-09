import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';

import {
  caseStateLabel,
  caseTypeLabel,
  evidenceCategoryLabel,
  marketLabel,
  relationLabel,
} from './labels.ts';
import {
  DECISION_BLOCKED_COPY,
  compareReviewQueue,
  pilotReviewIsVisible,
  presentReviewScreen,
  reviewActionsBlocked,
  sortReviewQueue,
} from './presentation.ts';
import {
  isReviewDenied,
  userFacingReviewMessage,
} from './reviewErrors.ts';
import {
  parseReviewCapabilities,
  parseReviewCase,
  parseReviewQueue,
} from './reviewRow.ts';
import {
  beginReviewLoad,
  createReviewPilotSession,
  markReviewBlurred,
  reviewUserKey,
  shouldApplyReviewResult,
  shouldResetReview,
} from './reviewSession.ts';
import { SPAIN_REVIEW_MARKET, SPAIN_REVIEW_SCOPE } from './types.ts';

const IDENTITY = '04010000-0000-4000-8000-0000000000a1';
const OWNERSHIP = '04010000-0000-4000-8000-0000000000b1';
const MANAGEMENT = '04010000-0000-4000-8000-0000000000c2';

describe('review row adapters', () => {
  it('adapts the three case classes and drops nothing private from the allowed fields', () => {
    const queue = parseReviewQueue([
      {
        case_id: IDENTITY,
        case_type: 'IDENTITY',
        market_country_code: 'ES',
        state: 'SUBMITTED',
        updated_at: '2026-10-09T10:00:00Z',
        evidence_categories: ['IDENTITY_PROVIDER_REFERENCE'],
      },
      {
        case_id: OWNERSHIP,
        case_type: 'OWNERSHIP',
        market_country_code: 'ES',
        state: 'RESUBMITTED',
        updated_at: '2026-10-09T11:00:00Z',
        evidence_categories: ['OWNERSHIP_ARTIFACT'],
      },
      {
        case_id: MANAGEMENT,
        case_type: 'MANAGEMENT',
        market_country_code: 'ES',
        state: 'IN_REVIEW',
        updated_at: '2026-10-09T12:00:00Z',
        evidence_categories: ['MANAGEMENT_DELEGATION_ARTIFACT'],
      },
    ]);

    assert.deepEqual(
      queue.map((item) => item.caseType),
      ['IDENTITY', 'OWNERSHIP', 'MANAGEMENT'],
    );

    const detail = parseReviewCase([
      {
        case_id: OWNERSHIP,
        case_type: 'OWNERSHIP',
        state: 'RESUBMITTED',
        market_country_code: 'ES',
        created_at: '2026-10-09T09:00:00Z',
        updated_at: '2026-10-09T11:00:00Z',
        subject_name: 'Visible Subject',
        equine_id: '04010000-0000-4000-8000-0000000000e1',
        equine_name: 'Pilot Horse',
        relation_type: 'PERSON',
        relation_role: 'OWNER',
        evidence: [
          { category: 'OWNERSHIP_ARTIFACT', document_country_code: 'FR' },
        ],
        evidence_sufficient: true,
      },
    ]);

    assert.equal(detail.subjectName, 'Visible Subject');
    assert.equal(detail.equineName, 'Pilot Horse');
    assert.equal(detail.evidence[0]?.documentCountryCode, 'FR');
    assert.equal(JSON.stringify(detail).includes('storage_path'), false);
    assert.equal(JSON.stringify(detail).includes('provider_reference'), false);
  });

  it('accepts only a current Spain capability', () => {
    assert.equal(
      pilotReviewIsVisible(
        parseReviewCapabilities([
          { scope_type: SPAIN_REVIEW_SCOPE, market_country_code: SPAIN_REVIEW_MARKET },
        ]),
      ),
      true,
    );
    assert.equal(pilotReviewIsVisible([]), false);
  });
});

describe('review labels and order', () => {
  it('shows unknown codes as No disponible', () => {
    assert.equal(caseTypeLabel('FUTURE'), 'No disponible');
    assert.equal(caseStateLabel('DRAFT'), 'No disponible');
    assert.equal(evidenceCategoryLabel('SECRET_BLOB'), 'No disponible');
    assert.equal(relationLabel('UNKNOWN'), 'No disponible');
    assert.equal(marketLabel('Spain'), 'No disponible');
    assert.equal(caseTypeLabel('IDENTITY'), 'Identidad');
    assert.equal(caseTypeLabel('OWNERSHIP'), 'Propiedad');
    assert.equal(caseTypeLabel('MANAGEMENT'), 'Gestión');
  });

  it('sorts by date, then type, then id', () => {
    const sorted = sortReviewQueue([
      queueItem(IDENTITY, 'IDENTITY', '2026-10-09T10:00:00Z'),
      queueItem(MANAGEMENT, 'MANAGEMENT', '2026-10-09T12:00:00Z'),
      queueItem(OWNERSHIP, 'OWNERSHIP', '2026-10-09T12:00:00Z'),
    ]);

    assert.deepEqual(
      sorted.map((item) => item.caseId),
      [MANAGEMENT, OWNERSHIP, IDENTITY],
    );
    assert.equal(
      compareReviewQueue(
        queueItem(IDENTITY, 'IDENTITY', '2026-10-09T10:00:00Z'),
        queueItem(IDENTITY, 'IDENTITY', '2026-10-09T10:00:00Z'),
      ),
      0,
    );
  });
});

describe('review screen states', () => {
  it('covers loading, empty, error, denial, and a blocked decision', () => {
    assert.equal(
      presentReviewScreen({
        hasSession: true,
        isLoading: true,
        hadAccess: false,
        denied: false,
        errorMessage: null,
        items: [],
        detail: { kind: 'none' },
      }).kind,
      'loading',
    );
    assert.equal(
      presentReviewScreen({
        hasSession: true,
        isLoading: false,
        hadAccess: false,
        denied: false,
        errorMessage: null,
        items: [],
        detail: { kind: 'none' },
      }).kind,
      'empty',
    );
    assert.equal(
      presentReviewScreen({
        hasSession: true,
        isLoading: false,
        hadAccess: false,
        denied: false,
        errorMessage: 'No se pudo consultar la revisión. Inténtalo de nuevo.',
        items: [],
        detail: { kind: 'none' },
      }).kind,
      'error',
    );
    assert.equal(
      presentReviewScreen({
        hasSession: true,
        isLoading: false,
        hadAccess: false,
        denied: true,
        errorMessage: null,
        items: [],
        detail: { kind: 'none' },
      }).kind,
      'unauthorized',
    );
    assert.equal(
      presentReviewScreen({
        hasSession: true,
        isLoading: false,
        hadAccess: true,
        denied: true,
        errorMessage: null,
        items: [],
        detail: { kind: 'unavailable' },
      }).kind,
      'suspended',
    );
    assert.match(DECISION_BLOCKED_COPY, /bloqueada/);
    assert.equal(DECISION_BLOCKED_COPY.includes('Aceptar'), false);
    assert.equal(DECISION_BLOCKED_COPY.includes('Rechazar'), false);
  });

  it('hides SQL and clears data when the account changes or the screen blurs', () => {
    assert.equal(
      userFacingReviewMessage({
        code: '42501',
        message: 'select storage_path from verification_evidence',
      }),
      'No se pudo consultar la revisión. Inténtalo de nuevo.',
    );
    assert.equal(isReviewDenied({ code: '42501', message: 'hidden' }), true);
    assert.equal(shouldResetReview('user-a', null), true);
    assert.equal(shouldResetReview('user-a', 'user-b'), true);
    assert.equal(reviewUserKey(undefined), null);

    const started = beginReviewLoad(createReviewPilotSession('user-a'), 'user-a');
    const blurred = markReviewBlurred(started.session);

    assert.equal(blurred.loading, false);
    assert.equal(
      shouldApplyReviewResult(started.requestSeq, blurred.requestSeq, blurred.screenActive),
      false,
    );
    assert.equal(reviewActionsBlocked(true, false), false);
    assert.equal(reviewActionsBlocked(false, true), false);
  });
});

describe('review client surface', () => {
  it('does not call review functions or render a decision button', () => {
    const sources = [
      'reviewService.ts',
      'useReviewPilot.ts',
      'usePilotReviewAccess.ts',
      '../../screens/ReviewPilotScreen.tsx',
    ].map((file) => readFileSync(new URL(file, import.meta.url), 'utf8'));
    const combined = sources.join('\n');

    assert.equal(combined.includes('review_identity_case'), false);
    assert.equal(combined.includes('review_equine_ownership_claim'), false);
    assert.equal(combined.includes('review_equine_management_claim'), false);
    assert.equal(combined.includes('>Aceptar<'), false);
    assert.equal(combined.includes('>Rechazar<'), false);
    assert.equal(combined.includes("rpc('get_my_review_capabilities')"), true);
    assert.equal(combined.includes("rpc('list_my_review_queue')"), true);
    assert.equal(combined.includes("rpc('get_my_review_case'"), true);
  });
});

function queueItem(
  caseId: string,
  caseType: string,
  updatedAt: string,
) {
  return {
    caseId,
    caseType,
    marketCountryCode: 'ES',
    state: 'SUBMITTED',
    updatedAt,
    evidenceCategories: [],
  };
}
