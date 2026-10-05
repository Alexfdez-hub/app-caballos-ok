import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  equineDisplayName,
  spainIdentityLabel,
  identitySubmitSucceeded,
  IDENTITY_REQUEST_NOTICE,
  presentManagement,
  presentOwnerships,
  presentSpainIdentity,
  reloadAfterSpainIdentityRequest,
  startIdentitySubmit,
} from './presentation.ts';
import { userFacingVerificationMessage } from './verificationErrors.ts';
import {
  parseIdentityCaseRows,
  parseVerificationStatusRows,
} from './verificationRow.ts';
import type { VerificationSnapshot } from './types.ts';

const EQUINE_A = '11111111-1111-4111-8111-111111111111';
const EQUINE_B = '22222222-2222-4222-8222-222222222222';
const EFFECTIVE_A = '33333333-3333-4333-8333-333333333333';
const EFFECTIVE_B = '44444444-4444-4444-8444-444444444444';
const CASE_A = '55555555-5555-4555-8555-555555555555';
const CASE_B = '66666666-6666-4666-8666-666666666666';

function snapshot(
  overrides: Partial<VerificationSnapshot> = {},
): VerificationSnapshot {
  return {
    statusRows: [],
    identityCases: [],
    equineNames: new Map(),
    ...overrides,
  };
}

describe('Spain identity presentation', () => {
  it('shows not verified when there are no cases and no status rows', () => {
    const view = presentSpainIdentity(snapshot());
    assert.equal(view.status, 'NOT_VERIFIED');
    assert.equal(view.statusLabel, 'No verificada');
    assert.equal(view.canRequest, true);
  });

  it('shows a pending request without treating the case as verified', () => {
    const view = presentSpainIdentity(
      snapshot({
        statusRows: [
          {
            subjectKind: 'IDENTITY',
            marketCountryCode: 'ES',
            equineId: null,
            effectiveId: null,
            statusCode: 'NOT_VERIFIED',
          },
        ],
        identityCases: [
          {
            caseId: CASE_A,
            state: 'SUBMITTED',
            marketCountryCode: 'ES',
            outcome: null,
            decidedAt: null,
          },
        ],
      }),
    );
    assert.equal(view.status, 'PENDING');
    assert.equal(view.canRequest, false);
    assert.notEqual(view.statusLabel, 'Verificada');
    for (const state of ['IN_REVIEW', 'RESUBMITTED'] as const) {
      assert.equal(
        presentSpainIdentity(
          snapshot({
            identityCases: [
              {
                caseId: CASE_A,
                state,
                marketCountryCode: 'ES',
                outcome: null,
                decidedAt: null,
              },
            ],
          }),
        ).status,
        'PENDING',
      );
    }
  });

  it('shows a rejected finished request when nothing is currently verified', () => {
    const view = presentSpainIdentity(
      snapshot({
        statusRows: [
          {
            subjectKind: 'IDENTITY',
            marketCountryCode: 'ES',
            equineId: null,
            effectiveId: null,
            statusCode: 'NOT_VERIFIED',
          },
        ],
        identityCases: [
          {
            caseId: CASE_A,
            state: 'REJECTED',
            marketCountryCode: 'ES',
            outcome: 'REJECTED',
            decidedAt: '2026-01-01T00:00:00.000Z',
          },
        ],
      }),
    );
    assert.equal(view.status, 'REJECTED');
    assert.equal(view.canRequest, true);
  });

  it('shows verified only from the predicate status', () => {
    const view = presentSpainIdentity(
      snapshot({
        statusRows: [
          {
            subjectKind: 'IDENTITY',
            marketCountryCode: 'ES',
            equineId: null,
            effectiveId: null,
            statusCode: 'VERIFIED',
          },
        ],
        identityCases: [
          {
            caseId: CASE_A,
            state: 'ACCEPTED',
            marketCountryCode: 'ES',
            outcome: 'ACCEPTED',
            decidedAt: '2026-02-01T00:00:00.000Z',
          },
        ],
      }),
    );
    assert.equal(view.status, 'VERIFIED');
    assert.equal(view.canRequest, false);
  });

  it('keeps a current verification ahead of an older pending case', () => {
    const view = presentSpainIdentity(
      snapshot({
        statusRows: [
          {
            subjectKind: 'IDENTITY',
            marketCountryCode: 'ES',
            equineId: null,
            effectiveId: null,
            statusCode: 'VERIFIED',
          },
        ],
        identityCases: [
          {
            caseId: CASE_A,
            state: 'SUBMITTED',
            marketCountryCode: 'ES',
            outcome: null,
            decidedAt: null,
          },
        ],
      }),
    );
    assert.equal(view.status, 'VERIFIED');
  });

  it('does not treat an accepted case alone as verified identity', () => {
    const view = presentSpainIdentity(
      snapshot({
        identityCases: [
          {
            caseId: CASE_A,
            state: 'ACCEPTED',
            marketCountryCode: 'ES',
            outcome: 'ACCEPTED',
            decidedAt: '2026-03-01T00:00:00.000Z',
          },
        ],
      }),
    );
    assert.equal(view.status, 'NOT_VERIFIED');
    assert.notEqual(view.statusLabel, 'Verificada');
  });

  it('fails closed on an unknown trust code', () => {
    const rows = parseVerificationStatusRows([
      {
        subject_kind: 'IDENTITY',
        market_country_code: 'ES',
        equine_id: null,
        effective_id: null,
        status_code: 'MAYBE',
      },
    ]);
    const view = presentSpainIdentity(
      snapshot({
        statusRows: rows,
      }),
    );
    assert.equal(rows[0]?.statusCode, 'UNKNOWN');
    assert.equal(view.status, 'UNAVAILABLE');
    assert.equal(view.canRequest, false);
  });

  it('rejects a malformed response', () => {
    assert.throws(
      () => parseVerificationStatusRows([{ subject_kind: 'IDENTITY' }]),
      /could not be read/,
    );
    assert.throws(() => parseIdentityCaseRows({ case_id: CASE_A }), /could not be read/);
  });
});

describe('equine relation presentation', () => {
  it('keeps ownership and management rows apart and hides raw identifiers', () => {
    const current = snapshot({
      statusRows: [
        {
          subjectKind: 'OWNERSHIP',
          marketCountryCode: null,
          equineId: EQUINE_A,
          effectiveId: EFFECTIVE_A,
          statusCode: 'VERIFIED',
        },
        {
          subjectKind: 'MANAGEMENT',
          marketCountryCode: null,
          equineId: EQUINE_B,
          effectiveId: EFFECTIVE_B,
          statusCode: 'NOT_VERIFIED',
        },
        {
          subjectKind: 'IDENTITY',
          marketCountryCode: 'ES',
          equineId: null,
          effectiveId: null,
          statusCode: 'NOT_VERIFIED',
        },
      ],
      equineNames: new Map([[EQUINE_A, 'Bruma']]),
    });

    const ownerships = presentOwnerships(current);
    const management = presentManagement(current);
    assert.deepEqual(
      ownerships.map((row) => row.displayName),
      ['Bruma'],
    );
    assert.equal(ownerships[0]?.statusLabel, 'Verificada');
    assert.equal(management[0]?.displayName, 'Equino');
    assert.equal(management[0]?.statusLabel, 'No verificada');
    assert.equal(management[0]?.displayName.includes(EQUINE_B), false);
    assert.equal(equineDisplayName(EQUINE_B, new Map()), 'Equino');
  });
});

describe('identity request flow', () => {
  it('ignores a second submit while one is in flight', () => {
    const started = startIdentitySubmit({ inFlight: false, notice: null });
    assert.ok(started);
    assert.equal(startIdentitySubmit(started), null);
  });

  it('reloads status after a successful submit', async () => {
    let loads = 0;
    let submits = 0;
    const next = snapshot();
    const loaded = await reloadAfterSpainIdentityRequest({
      submit: async () => {
        submits += 1;
      },
      load: async () => {
        loads += 1;
        return next;
      },
    });
    assert.equal(submits, 1);
    assert.equal(loads, 1);
    assert.equal(loaded, next);
    assert.equal(identitySubmitSucceeded().notice, IDENTITY_REQUEST_NOTICE);
    assert.match(IDENTITY_REQUEST_NOTICE, /no queda verificada/);
  });

  it('hides SQL and identifiers from the visible error', () => {
    const message = userFacingVerificationMessage(
      new Error(
        `duplicate key value violates unique constraint identity_verification_cases ${CASE_B}`,
      ),
    );
    assert.equal(
      message,
      'No se pudo completar la verificación. Inténtalo de nuevo.',
    );
    assert.equal(message.includes(CASE_B), false);
    assert.equal(message.toLowerCase().includes('duplicate'), false);
    assert.equal(message.toLowerCase().includes('identity_verification'), false);
  });
});

describe('Spanish labels', () => {
  it('maps stable codes to Spanish copy outside the service parser', () => {
    assert.equal(spainIdentityLabel('VERIFIED'), 'Verificada');
    assert.equal(spainIdentityLabel('PENDING'), 'Solicitud pendiente');
    assert.equal(spainIdentityLabel('REJECTED'), 'No aceptada');
    assert.equal(spainIdentityLabel('NOT_VERIFIED'), 'No verificada');
    assert.equal(spainIdentityLabel('UNAVAILABLE'), 'No disponible');
  });
});
