import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import type {
  EquineManagementAssignment,
  EquineOwnership,
} from '../equines/types.ts';
import { relationStatusLabel } from './presentation.ts';
import {
  CLAIM_RECORDED_NOTICE,
  CLAIM_RECONCILE_ERROR,
  claimRequestLabel,
  managementClaimPayload,
  ownershipClaimPayload,
  presentRelationClaims,
  type ManagementClaimRecord,
  type OwnershipClaimRecord,
} from './relationClaims.ts';
import {
  attemptRelationClaimSubmit,
  beginRelationClaimModelRefresh,
  beginRelationClaimModelSubmit,
  blurRelationClaimModel,
  createRelationClaimModel,
  finishRelationClaimModelRefresh,
  focusRelationClaimModel,
  reconcileRelationClaimSnapshot,
  RelationClaimUnavailable,
  relationClaimModelFlight,
  relationClaimModelSection,
  settleRelationClaimModelFailure,
  settleRelationClaimModelSuccess,
  switchRelationClaimModel,
  type RelationClaimModel,
} from './relationClaimFlow.ts';
import type { RelationClaimSnapshot } from './relationClaimService.ts';
import {
  beginRelationClaimRefresh,
  beginRelationClaimSubmit,
  createRelationClaimSession,
  finishRelationClaimRefresh,
  markRelationClaimsBlurred,
  markRelationClaimsFocused,
  relationClaimFlight,
  settleRelationClaimSubmit,
  switchRelationClaimContext,
} from './relationClaimSession.ts';
import {
  switchVerificationUser,
  shouldApplyVerificationResult,
  createVerificationSession,
} from './verificationSession.ts';
import { userFacingVerificationMessage, VerificationResponseError } from './verificationErrors.ts';
import type { VerificationStatusRow } from './types.ts';

const EQUINE = '11111111-1111-4111-8111-111111111111';
const OTHER_EQUINE = '22222222-2222-4222-8222-222222222222';
const OWNERSHIP_ID = '33333333-3333-4333-8333-333333333333';
const ASSIGNMENT_ID = '44444444-4444-4444-8444-444444444444';
const CLAIM_ID = '55555555-5555-4555-8555-555555555555';
const VALID_FROM = '2020-01-01T00:00:00+00';

function ownership(overrides: Partial<EquineOwnership> = {}): EquineOwnership {
  return {
    ownershipId: OWNERSHIP_ID,
    equineId: EQUINE,
    equineName: 'Caballo',
    equineType: 'HORSE',
    ownerType: 'PERSON',
    ownershipPercentage: 60,
    status: 'ACTIVE',
    isCurrentlyEffective: true,
    startedAt: VALID_FROM,
    endedAt: null,
    ...overrides,
  };
}

function assignment(
  overrides: Partial<EquineManagementAssignment> = {},
): EquineManagementAssignment {
  return {
    assignmentId: ASSIGNMENT_ID,
    equineId: EQUINE,
    equineName: 'Caballo',
    equineType: 'HORSE',
    managementRole: 'PRIMARY_MANAGER',
    status: 'ACTIVE',
    isCurrentlyEffective: true,
    validFrom: VALID_FROM,
    validUntil: null,
    ...overrides,
  };
}

function trust(
  kind: 'OWNERSHIP' | 'MANAGEMENT',
  effectiveId: string,
  statusCode: VerificationStatusRow['statusCode'] = 'NOT_VERIFIED',
): VerificationStatusRow {
  return {
    subjectKind: kind,
    marketCountryCode: null,
    equineId: EQUINE,
    effectiveId,
    statusCode,
  };
}

describe('relation claim payloads', () => {
  it('copies the effective ownership percentage and id', () => {
    const payload = ownershipClaimPayload(ownership());
    assert.deepEqual(payload, {
      p_equine_id: EQUINE,
      p_market_country_code: 'ES',
      p_owner_type: 'PERSON',
      p_owner_center_id: null,
      p_ownership_percentage: 60,
      p_effective_ownership_id: OWNERSHIP_ID,
    });
  });

  it('cannot build a percentage other than the effective row', () => {
    const current = ownership({ ownershipPercentage: 60 });
    const drifted = ownership({ ownershipPercentage: 40 });
    assert.equal(ownershipClaimPayload(current)?.p_ownership_percentage, 60);
    assert.equal(ownershipClaimPayload(drifted)?.p_ownership_percentage, 40);
    assert.notEqual(
      ownershipClaimPayload(drifted)?.p_ownership_percentage,
      current.ownershipPercentage,
    );
    const section = presentRelationClaims({
      equineId: EQUINE,
      ownerships: [current],
      assignments: [],
      ownershipClaims: [],
      managementClaims: [],
      trustRows: [trust('OWNERSHIP', OWNERSHIP_ID)],
    });
    assert.equal(section.ownership.ownershipPayload?.p_ownership_percentage, 60);
    assert.equal(section.ownership.trustLabel, relationStatusLabel('NOT_VERIFIED'));
    assert.equal('ownershipPercentage' in section.ownership, false);
  });

  it('copies the management role and the effective window', () => {
    const payload = managementClaimPayload(assignment());
    assert.equal(payload?.p_management_role, 'PRIMARY_MANAGER');
    assert.equal(payload?.p_valid_from, VALID_FROM);
    assert.equal(payload?.p_valid_until, null);
    assert.equal(payload?.p_effective_assignment_id, ASSIGNMENT_ID);
    assert.notEqual(payload?.p_valid_from, new Date().toISOString());
  });

  it('refuses a historical or expired assignment', () => {
    assert.equal(
      managementClaimPayload(
        assignment({
          status: 'ENDED',
          isCurrentlyEffective: false,
          validFrom: '2019-01-01T00:00:00+00',
          validUntil: '2019-06-01T00:00:00+00',
        }),
      ),
      null,
    );
    assert.equal(
      managementClaimPayload(
        assignment({
          isCurrentlyEffective: false,
          validFrom: '2099-01-01T00:00:00+00',
        }),
      ),
      null,
    );
    assert.equal(
      ownershipClaimPayload(
        ownership({
          status: 'ENDED',
          isCurrentlyEffective: false,
          endedAt: '2019-06-01T00:00:00+00',
        }),
      ),
      null,
    );
  });

  it('shows an open request and accepts a verified row without reusing an old decision', () => {
    assert.equal(claimRequestLabel('SUBMITTED'), 'Solicitud pendiente');
    assert.equal(claimRequestLabel('IN_REVIEW'), 'En revisión');
    assert.equal(claimRequestLabel('ACCEPTED'), 'Aceptada');
    assert.equal(claimRequestLabel('REJECTED'), 'No aceptada');
    assert.equal(claimRequestLabel('UNAVAILABLE'), 'No disponible');

    const claim = (
      state: OwnershipClaimRecord['state'],
    ): OwnershipClaimRecord => ({
      claimId: CLAIM_ID,
      equineId: EQUINE,
      state,
      marketCountryCode: 'ES',
      ownerType: 'PERSON',
      ownershipPercentage: 60,
      decidedAt: '2024-01-01T00:00:00+00',
    });

    for (const [state, label] of [
      ['SUBMITTED', 'Solicitud pendiente'],
      ['IN_REVIEW', 'En revisión'],
    ] as const) {
      const section = presentRelationClaims({
        equineId: EQUINE,
        ownerships: [ownership()],
        assignments: [],
        ownershipClaims: [claim(state)],
        managementClaims: [],
        trustRows: [trust('OWNERSHIP', OWNERSHIP_ID)],
      });
      assert.equal(section.ownership.statusLabel, label);
      assert.equal(section.ownership.canSubmit, false);
    }

    const verified = presentRelationClaims({
      equineId: EQUINE,
      ownerships: [ownership()],
      assignments: [],
      ownershipClaims: [],
      managementClaims: [],
      trustRows: [trust('OWNERSHIP', OWNERSHIP_ID, 'VERIFIED')],
    });
    assert.equal(verified.ownership.statusLabel, 'Aceptada');
    assert.equal(verified.ownership.canSubmit, false);
  });

  it('copies a future management end when the row is currently effective', () => {
    const until = '2099-01-01T00:00:00+00';
    const payload = managementClaimPayload(
      assignment({
        isCurrentlyEffective: true,
        validUntil: until,
      }),
    );
    assert.equal(payload?.p_valid_from, VALID_FROM);
    assert.equal(payload?.p_valid_until, until);
    assert.equal(
      managementClaimPayload(
        assignment({
          status: 'ENDED',
          isCurrentlyEffective: false,
          validFrom: '2019-01-01T00:00:00+00',
          validUntil: '2019-06-01T00:00:00+00',
        }),
      ),
      null,
    );
  });

  it('does not treat an old finished claim as the decision for a new effective row', () => {
    const oldOwnership: OwnershipClaimRecord = {
      claimId: CLAIM_ID,
      equineId: EQUINE,
      state: 'ACCEPTED',
      marketCountryCode: 'ES',
      ownerType: 'PERSON',
      ownershipPercentage: 60,
      decidedAt: '2024-01-01T00:00:00+00',
    };
    const rejectedOwnership: OwnershipClaimRecord = {
      ...oldOwnership,
      state: 'REJECTED',
    };
    const ownershipSection = presentRelationClaims({
      equineId: EQUINE,
      ownerships: [ownership({ ownershipId: OWNERSHIP_ID })],
      assignments: [],
      ownershipClaims: [oldOwnership, rejectedOwnership],
      managementClaims: [],
      trustRows: [trust('OWNERSHIP', OWNERSHIP_ID, 'NOT_VERIFIED')],
    });
    assert.equal(ownershipSection.ownership.statusLabel, null);
    assert.equal(ownershipSection.ownership.canSubmit, true);
    assert.notEqual(ownershipSection.ownership.statusLabel, 'Aceptada');
    assert.notEqual(ownershipSection.ownership.statusLabel, 'No aceptada');

    const oldManagement: ManagementClaimRecord = {
      claimId: CLAIM_ID,
      equineId: EQUINE,
      state: 'ACCEPTED',
      marketCountryCode: 'ES',
      managerType: 'PERSON',
      managementRole: 'PRIMARY_MANAGER',
      decidedAt: '2024-01-01T00:00:00+00',
    };
    const managementSection = presentRelationClaims({
      equineId: EQUINE,
      ownerships: [],
      assignments: [assignment({ assignmentId: ASSIGNMENT_ID })],
      ownershipClaims: [],
      managementClaims: [
        oldManagement,
        { ...oldManagement, state: 'REJECTED' },
      ],
      trustRows: [trust('MANAGEMENT', ASSIGNMENT_ID, 'NOT_VERIFIED')],
    });
    assert.equal(managementSection.management.statusLabel, null);
    assert.equal(managementSection.management.canSubmit, true);
    assert.equal(managementSection.management.managementPayload?.p_management_role, 'PRIMARY_MANAGER');
  });

  it('lets an open center claim block the person submit for the same equine', () => {
    const ownershipSection = presentRelationClaims({
      equineId: EQUINE,
      ownerships: [ownership()],
      assignments: [],
      ownershipClaims: [
        {
          claimId: CLAIM_ID,
          equineId: EQUINE,
          state: 'SUBMITTED',
          marketCountryCode: 'ES',
          ownerType: 'CENTER',
          ownershipPercentage: 60,
          decidedAt: null,
        },
      ],
      managementClaims: [],
      trustRows: [trust('OWNERSHIP', OWNERSHIP_ID, 'NOT_VERIFIED')],
    });
    assert.equal(ownershipSection.ownership.canSubmit, false);
    assert.equal(ownershipSection.ownership.statusLabel, 'Solicitud pendiente');

    const managementSection = presentRelationClaims({
      equineId: EQUINE,
      ownerships: [],
      assignments: [assignment()],
      ownershipClaims: [],
      managementClaims: [
        {
          claimId: CLAIM_ID,
          equineId: EQUINE,
          state: 'IN_REVIEW',
          marketCountryCode: 'ES',
          managerType: 'CENTER',
          managementRole: 'PRIMARY_MANAGER',
          decidedAt: null,
        },
      ],
      trustRows: [trust('MANAGEMENT', ASSIGNMENT_ID, 'NOT_VERIFIED')],
    });
    assert.equal(managementSection.management.canSubmit, false);
    assert.equal(managementSection.management.statusLabel, 'En revisión');
  });

  it('does not let a finished center claim block a new person submit', () => {
    const ownershipSection = presentRelationClaims({
      equineId: EQUINE,
      ownerships: [ownership()],
      assignments: [],
      ownershipClaims: [
        {
          claimId: CLAIM_ID,
          equineId: EQUINE,
          state: 'REJECTED',
          marketCountryCode: 'ES',
          ownerType: 'CENTER',
          ownershipPercentage: 60,
          decidedAt: '2024-01-01T00:00:00+00',
        },
      ],
      managementClaims: [],
      trustRows: [trust('OWNERSHIP', OWNERSHIP_ID, 'NOT_VERIFIED')],
    });
    assert.equal(ownershipSection.ownership.canSubmit, true);
    assert.equal(ownershipSection.ownership.statusLabel, null);

    const managementSection = presentRelationClaims({
      equineId: EQUINE,
      ownerships: [],
      assignments: [assignment()],
      ownershipClaims: [],
      managementClaims: [
        {
          claimId: CLAIM_ID,
          equineId: EQUINE,
          state: 'ACCEPTED',
          marketCountryCode: 'ES',
          managerType: 'CENTER',
          managementRole: 'PRIMARY_MANAGER',
          decidedAt: '2024-01-01T00:00:00+00',
        },
      ],
      trustRows: [trust('MANAGEMENT', ASSIGNMENT_ID, 'NOT_VERIFIED')],
    });
    assert.equal(managementSection.management.canSubmit, true);
    assert.equal(managementSection.management.statusLabel, null);
  });

  it('explains when no current relation can be submitted', () => {
    const section = presentRelationClaims({
      equineId: EQUINE,
      ownerships: [ownership({ equineId: OTHER_EQUINE })],
      assignments: [],
      ownershipClaims: [],
      managementClaims: [] as ManagementClaimRecord[],
      trustRows: [],
    });
    assert.equal(section.ownership.canSubmit, false);
    assert.equal(section.ownership.ownershipPayload, null);
    assert.match(section.ownership.explanation ?? '', /propiedad vigente/);
    assert.equal(section.management.canSubmit, false);
    assert.match(section.management.explanation ?? '', /responsabilidad vigente/);
  });
});

describe('relation claim submit session', () => {
  it('sends one request when the action is pressed twice', () => {
    let current = markRelationClaimsFocused(
      switchRelationClaimContext(createRelationClaimSession('user-a'), 'user-a', EQUINE),
    );
    const first = beginRelationClaimSubmit(current, 'user-a', EQUINE);
    assert.ok(first);
    current = first.session;
    assert.equal(beginRelationClaimSubmit(current, 'user-a', EQUINE), null);
    assert.equal(current.inFlight, true);
  });

  it('drops a response after the account changes', () => {
    let current = markRelationClaimsFocused(
      switchRelationClaimContext(createRelationClaimSession('user-a'), 'user-a', EQUINE),
    );
    const started = beginRelationClaimSubmit(current, 'user-a', EQUINE);
    assert.ok(started);
    current = switchRelationClaimContext(started.session, 'user-b', EQUINE);
    assert.equal(current.inFlight, false);
    assert.equal(current.notice, null);
    assert.equal(current.errorMessage, null);
    const settled = settleRelationClaimSubmit(current, started.request, {
      ok: true,
      notice: CLAIM_RECORDED_NOTICE,
    });
    assert.equal(settled.apply, false);
    assert.equal(settled.session, current);
    assert.equal(settled.session.notice, null);
    assert.equal(settled.session.errorMessage, null);
  });

  it('keeps the new account locked when the previous submit finishes late', () => {
    let current = markRelationClaimsFocused(
      switchRelationClaimContext(createRelationClaimSession('user-a'), 'user-a', EQUINE),
    );
    const accountA = beginRelationClaimSubmit(current, 'user-a', EQUINE);
    assert.ok(accountA);
    current = switchRelationClaimContext(accountA.session, 'user-b', EQUINE);
    const accountB = beginRelationClaimSubmit(current, 'user-b', EQUINE);
    assert.ok(accountB);
    current = accountB.session;
    const late = settleRelationClaimSubmit(current, accountA.request, {
      ok: true,
      notice: CLAIM_RECORDED_NOTICE,
    });
    assert.equal(late.apply, false);
    assert.equal(late.session, current);
    assert.equal(late.session.inFlight, true);
    assert.equal(late.session.userKey, 'user-b');
    assert.equal(beginRelationClaimSubmit(late.session, 'user-b', EQUINE), null);
  });

  it('releases the button after a recoverable or definitive failure', () => {
    let current = markRelationClaimsFocused(
      switchRelationClaimContext(createRelationClaimSession('user-a'), 'user-a', EQUINE),
    );
    const started = beginRelationClaimSubmit(current, 'user-a', EQUINE);
    assert.ok(started);
    const recoverable = settleRelationClaimSubmit(started.session, started.request, {
      ok: false,
      errorMessage: userFacingVerificationMessage(new Error('Network request failed')),
    });
    assert.equal(recoverable.apply, true);
    assert.equal(recoverable.session.inFlight, false);
    assert.equal(
      recoverable.session.errorMessage,
      'No se pudo completar la verificación. Inténtalo de nuevo.',
    );
    assert.equal(beginRelationClaimSubmit(recoverable.session, 'user-a', EQUINE) !== null, true);

    const again = beginRelationClaimSubmit(recoverable.session, 'user-a', EQUINE);
    assert.ok(again);
    const definitive = userFacingVerificationMessage({
      message: `Verification request is not available ${CLAIM_ID}`,
      code: '42501',
    });
    const settled = settleRelationClaimSubmit(again.session, again.request, {
      ok: false,
      errorMessage: definitive,
    });
    assert.equal(settled.session.inFlight, false);
    assert.equal(settled.session.errorMessage?.includes(CLAIM_ID), false);
    assert.equal(settled.session.errorMessage?.includes('42501'), false);
    assert.equal(settled.session.errorMessage?.toLowerCase().includes('select '), false);
  });

  it('settles a successful submit while blurred and shows the pending claim on return', () => {
    let current = markRelationClaimsFocused(
      switchRelationClaimContext(createRelationClaimSession('user-a'), 'user-a', EQUINE),
    );
    const started = beginRelationClaimSubmit(current, 'user-a', EQUINE);
    assert.ok(started);
    current = markRelationClaimsBlurred(started.session);
    const settled = settleRelationClaimSubmit(current, started.request, {
      ok: true,
      notice: CLAIM_RECORDED_NOTICE,
    });
    assert.equal(settled.apply, false);
    assert.equal(settled.session.inFlight, false);
    assert.equal(settled.session.notice, CLAIM_RECORDED_NOTICE);
    const returned = markRelationClaimsFocused(settled.session);
    const flight = relationClaimFlight(returned);
    assert.equal(flight.inFlight, returned.inFlight);
    assert.equal(flight.inFlight, false);
    assert.equal(flight.notice, CLAIM_RECORDED_NOTICE);
    const section = presentRelationClaims({
      equineId: EQUINE,
      ownerships: [ownership()],
      assignments: [],
      ownershipClaims: [
        {
          claimId: CLAIM_ID,
          equineId: EQUINE,
          state: 'SUBMITTED',
          marketCountryCode: 'ES',
          ownerType: 'PERSON',
          ownershipPercentage: 60,
          decidedAt: null,
        },
      ],
      managementClaims: [],
      trustRows: [trust('OWNERSHIP', OWNERSHIP_ID, 'NOT_VERIFIED')],
    });
    assert.equal(section.ownership.statusLabel, 'Solicitud pendiente');
    assert.equal(section.ownership.canSubmit, false);
  });

  it('clears a recoverable failure that finished while blurred and lets the retry send', () => {
    let current = markRelationClaimsFocused(
      switchRelationClaimContext(createRelationClaimSession('user-a'), 'user-a', EQUINE),
    );
    const started = beginRelationClaimSubmit(current, 'user-a', EQUINE);
    assert.ok(started);
    current = markRelationClaimsBlurred(started.session);
    const settled = settleRelationClaimSubmit(current, started.request, {
      ok: false,
      errorMessage: userFacingVerificationMessage(new Error('Network request failed')),
    });
    assert.equal(settled.apply, false);
    assert.equal(settled.session.inFlight, false);
    const returned = markRelationClaimsFocused(settled.session);
    const flight = relationClaimFlight(returned);
    assert.equal(flight.inFlight, false);
    assert.equal(flight.inFlight, returned.inFlight);
    const retry = beginRelationClaimSubmit(returned, 'user-a', EQUINE);
    assert.ok(retry);
    assert.equal(retry.session.inFlight, true);
    assert.notEqual(retry.request.requestSeq, started.request.requestSeq);
  });

  it('keeps the visible flight aligned with the session when refresh finishes around a submit', () => {
    let current = markRelationClaimsFocused(
      switchRelationClaimContext(createRelationClaimSession('user-a'), 'user-a', EQUINE),
    );
    const started = beginRelationClaimSubmit(current, 'user-a', EQUINE);
    assert.ok(started);
    current = markRelationClaimsBlurred(started.session);
    const refresh = beginRelationClaimRefresh(current);
    assert.ok(refresh);
    assert.equal(refresh.session.inFlight, true);
    assert.equal(refresh.session.requestSeq, started.request.requestSeq);
    const hiddenSuccess = finishRelationClaimRefresh(refresh.session, refresh.refresh, {
      ok: true,
    });
    assert.equal(hiddenSuccess.paint, false);
    assert.equal(hiddenSuccess.session.inFlight, true);
    const visible = markRelationClaimsFocused(hiddenSuccess.session);
    const success = finishRelationClaimRefresh(visible, refresh.refresh, { ok: true });
    assert.equal(success.paint, true);
    assert.equal(success.session.inFlight, true);
    assert.equal(relationClaimFlight(success.session).inFlight, success.session.inFlight);

    const failure = finishRelationClaimRefresh(visible, refresh.refresh, {
      ok: false,
      errorMessage: 'No se pudo completar la verificación. Inténtalo de nuevo.',
    });
    assert.equal(failure.paint, true);
    assert.equal(failure.session.inFlight, true);
    assert.equal(relationClaimFlight(failure.session).inFlight, true);
    assert.equal(failure.session.errorMessage, null);
  });

  it('does not let a stale result from another equine change the current submit', () => {
    let current = markRelationClaimsFocused(
      switchRelationClaimContext(createRelationClaimSession('user-a'), 'user-a', EQUINE),
    );
    const equineA = beginRelationClaimSubmit(current, 'user-a', EQUINE);
    assert.ok(equineA);
    current = switchRelationClaimContext(equineA.session, 'user-a', OTHER_EQUINE);
    const equineB = beginRelationClaimSubmit(current, 'user-a', OTHER_EQUINE);
    assert.ok(equineB);
    const late = settleRelationClaimSubmit(equineB.session, equineA.request, {
      ok: true,
      notice: CLAIM_RECORDED_NOTICE,
    });
    assert.equal(late.apply, false);
    assert.equal(late.session, equineB.session);
    assert.equal(late.session.inFlight, true);
    assert.equal(late.session.equineId, OTHER_EQUINE);
    assert.equal(beginRelationClaimSubmit(late.session, 'user-a', OTHER_EQUINE), null);
  });
});

function claimSnapshot(withOpenClaim: boolean): RelationClaimSnapshot {
  return {
    ownerships: [ownership()],
    assignments: [],
    ownershipClaims: withOpenClaim
      ? [
          {
            claimId: CLAIM_ID,
            equineId: EQUINE,
            state: 'SUBMITTED',
            marketCountryCode: 'ES',
            ownerType: 'PERSON',
            ownershipPercentage: 60,
            decidedAt: null,
          },
        ]
      : [],
    managementClaims: [],
    trustRows: [trust('OWNERSHIP', OWNERSHIP_ID, 'NOT_VERIFIED')],
  };
}

function confirmedBlurredSubmit(): RelationClaimModel {
  const open = focusRelationClaimModel(createRelationClaimModel('user-a', EQUINE));
  const ready = { ...open, visible: claimSnapshot(false) };
  const started = beginRelationClaimModelSubmit(ready, 'OWNERSHIP', 'user-a', EQUINE);
  assert.ok(started);
  const blurred = blurRelationClaimModel(started.model);
  const settled = settleRelationClaimModelSuccess(
    blurred,
    started.request,
    claimSnapshot(true),
    CLAIM_RECORDED_NOTICE,
    'OWNERSHIP',
  );
  assert.equal(settled.apply, false);
  return focusRelationClaimModel(settled.model);
}

describe('relation claim return coordination', () => {
  it('blocks a second submit on return before refresh finishes', () => {
    let calls = 0;
    const returned = confirmedBlurredSubmit();
    calls += 1;
    const section = relationClaimModelSection(returned, EQUINE);
    assert.equal(returned.visible, returned.held);
    assert.equal(section?.ownership.statusLabel, 'Solicitud pendiente');
    assert.equal(section?.ownership.canSubmit, false);
    assert.equal(relationClaimModelFlight(returned).inFlight, false);
    assert.equal(relationClaimModelFlight(returned).notice, CLAIM_RECORDED_NOTICE);
    assert.equal(
      beginRelationClaimModelSubmit(returned, 'OWNERSHIP', 'user-a', EQUINE),
      null,
    );
    assert.equal(calls, 1);
  });

  it('keeps the claim closed after the return refresh succeeds', () => {
    const returned = confirmedBlurredSubmit();
    const started = beginRelationClaimModelRefresh(returned);
    assert.ok(started);
    const finished = finishRelationClaimModelRefresh(started.model, started.refresh, {
      ok: true,
      snapshot: claimSnapshot(true),
    });
    assert.equal(finished.paint, true);
    const section = relationClaimModelSection(finished.model, EQUINE);
    assert.equal(section?.ownership.statusLabel, 'Solicitud pendiente');
    assert.equal(section?.ownership.canSubmit, false);
    assert.equal(
      beginRelationClaimModelSubmit(finished.model, 'OWNERSHIP', 'user-a', EQUINE),
      null,
    );
  });

  it('does not reopen a confirmed submit when the return refresh fails', () => {
    const returned = confirmedBlurredSubmit();
    const started = beginRelationClaimModelRefresh(returned);
    assert.ok(started);
    const finished = finishRelationClaimModelRefresh(started.model, started.refresh, {
      ok: false,
      errorMessage: 'No se pudo completar la verificación. Inténtalo de nuevo.',
    });
    assert.equal(finished.paint, true);
    assert.equal(finished.model.visible, returned.held);
    assert.notEqual(finished.model.visible, null);
    assert.equal(relationClaimModelFlight(finished.model).notice, CLAIM_RECORDED_NOTICE);
    assert.equal(relationClaimModelSection(finished.model, EQUINE)?.ownership.canSubmit, false);
    assert.equal(
      beginRelationClaimModelSubmit(finished.model, 'OWNERSHIP', 'user-a', EQUINE),
      null,
    );
  });

  it('stays blocked when a later refresh still offers another submit', () => {
    const returned = confirmedBlurredSubmit();
    const lagging = claimSnapshot(false);
    assert.equal(
      presentRelationClaims({ equineId: EQUINE, ...lagging }).ownership.canSubmit,
      true,
    );
    const started = beginRelationClaimModelRefresh(returned);
    assert.ok(started);
    const finished = finishRelationClaimModelRefresh(started.model, started.refresh, {
      ok: true,
      snapshot: lagging,
    });
    assert.equal(relationClaimModelSection(finished.model, EQUINE)?.ownership.canSubmit, false);
    assert.equal(
      beginRelationClaimModelSubmit(finished.model, 'OWNERSHIP', 'user-a', EQUINE),
      null,
    );
  });

  it('sends exactly one retry after a recoverable failure that settled while blurred', () => {
    let calls = 0;
    const open = focusRelationClaimModel(createRelationClaimModel('user-a', EQUINE));
    const ready = { ...open, visible: claimSnapshot(false) };
    const started = beginRelationClaimModelSubmit(ready, 'OWNERSHIP', 'user-a', EQUINE);
    assert.ok(started);
    calls += 1;
    const settled = settleRelationClaimModelFailure(
      blurRelationClaimModel(started.model),
      started.request,
      'No se pudo completar la verificación. Inténtalo de nuevo.',
    );
    assert.equal(settled.apply, false);
    const returned = focusRelationClaimModel(settled.model);
    calls = 0;
    const retry = beginRelationClaimModelSubmit(returned, 'OWNERSHIP', 'user-a', EQUINE);
    assert.ok(retry);
    calls += 1;
    assert.equal(
      beginRelationClaimModelSubmit(retry.model, 'OWNERSHIP', 'user-a', EQUINE),
      null,
    );
    assert.equal(calls, 1);
  });

  it('does not let account A leave a confirmed snapshot on account B', () => {
    const open = focusRelationClaimModel(createRelationClaimModel('user-a', EQUINE));
    const started = beginRelationClaimModelSubmit(
      { ...open, visible: claimSnapshot(false) },
      'OWNERSHIP',
      'user-a',
      EQUINE,
    );
    assert.ok(started);
    const accountB = focusRelationClaimModel(
      switchRelationClaimModel(started.model, 'user-b', EQUINE),
    );
    const late = settleRelationClaimModelSuccess(
      accountB,
      started.request,
      claimSnapshot(true),
      CLAIM_RECORDED_NOTICE,
      'OWNERSHIP',
    );
    assert.equal(late.apply, false);
    assert.equal(late.model, accountB);
    assert.equal(late.model.held, null);
    assert.equal(late.model.confirmed.OWNERSHIP, false);
    const ready = { ...late.model, visible: claimSnapshot(false) };
    const next = beginRelationClaimModelSubmit(ready, 'OWNERSHIP', 'user-b', EQUINE);
    assert.ok(next);
    assert.equal(next.model.session.inFlight, true);
  });

  it('does not let equine A leave a confirmed snapshot on equine B', () => {
    const open = focusRelationClaimModel(createRelationClaimModel('user-a', EQUINE));
    const started = beginRelationClaimModelSubmit(
      { ...open, visible: claimSnapshot(false) },
      'OWNERSHIP',
      'user-a',
      EQUINE,
    );
    assert.ok(started);
    const equineB = focusRelationClaimModel(
      switchRelationClaimModel(started.model, 'user-a', OTHER_EQUINE),
    );
    const late = settleRelationClaimModelSuccess(
      equineB,
      started.request,
      claimSnapshot(true),
      CLAIM_RECORDED_NOTICE,
      'OWNERSHIP',
    );
    assert.equal(late.model.held, null);
    assert.equal(late.model.session.equineId, OTHER_EQUINE);
    assert.equal(late.model.session.inFlight, false);
    const ready = {
      ...late.model,
      visible: {
        ...claimSnapshot(false),
        ownerships: [ownership({ equineId: OTHER_EQUINE })],
      },
    };
    const next = beginRelationClaimModelSubmit(ready, 'OWNERSHIP', 'user-a', OTHER_EQUINE);
    assert.ok(next);
  });
});

function readyClaimModel(): RelationClaimModel {
  const open = focusRelationClaimModel(createRelationClaimModel('user-a', EQUINE));
  return { ...open, visible: claimSnapshot(false) };
}

async function driveClaimSubmit(
  initial: RelationClaimModel,
  mutate: (box: { model: RelationClaimModel }) => Promise<void>,
  loadSnapshot: () => Promise<RelationClaimSnapshot>,
) {
  const box = { model: initial };
  const result = await attemptRelationClaimSubmit({
    model: box.model,
    kind: 'OWNERSHIP',
    userKey: box.model.session.userKey,
    equineId: box.model.session.equineId ?? EQUINE,
    notice: CLAIM_RECORDED_NOTICE,
    readModel: () => box.model,
    writeModel: (next) => {
      box.model = next;
    },
    mutate: () => mutate(box),
    loadSnapshot,
  });
  return { ...result, model: box.model };
}

describe('relation claim mutation and snapshot read', () => {
  it('keeps a focused submit blocked when the first snapshot read fails', async () => {
    let calls = 0;
    const first = await driveClaimSubmit(
      readyClaimModel(),
      async () => {
        calls += 1;
      },
      async () => {
        throw new Error('timeout');
      },
    );
    assert.equal(first.sent, true);
    assert.equal(first.confirmed, true);
    assert.equal(first.model.session.screenActive, true);
    assert.equal(first.model.session.inFlight, false);
    assert.equal(first.model.confirmed.OWNERSHIP, true);
    assert.equal(first.model.session.notice, CLAIM_RECORDED_NOTICE);
    assert.equal(first.model.session.errorMessage, CLAIM_RECONCILE_ERROR);
    assert.equal(
      presentRelationClaims({ equineId: EQUINE, ...claimSnapshot(false) }).ownership.canSubmit,
      true,
    );
    assert.equal(relationClaimModelSection(first.model, EQUINE)?.ownership.canSubmit, false);
    const second = await driveClaimSubmit(
      first.model,
      async () => {
        calls += 1;
      },
      async () => claimSnapshot(true),
    );
    assert.equal(second.sent, false);
    assert.equal(calls, 1);
  });

  it('keeps the block across blur and focus and reconciles on a later read', async () => {
    let calls = 0;
    const first = await driveClaimSubmit(
      readyClaimModel(),
      async (box) => {
        calls += 1;
        box.model = blurRelationClaimModel(box.model);
      },
      async () => {
        throw new Error('timeout');
      },
    );
    assert.equal(first.model.session.screenActive, false);
    assert.equal(first.model.confirmed.OWNERSHIP, true);
    assert.equal(first.model.session.notice, CLAIM_RECORDED_NOTICE);
    const returned = focusRelationClaimModel(first.model);
    assert.equal(relationClaimModelSection(returned, EQUINE)?.ownership.canSubmit, false);
    const second = await driveClaimSubmit(
      returned,
      async () => {
        calls += 1;
      },
      async () => claimSnapshot(true),
    );
    assert.equal(second.sent, false);
    const reconciled = reconcileRelationClaimSnapshot(
      returned,
      {
        requestSeq: returned.session.requestSeq,
        userKey: returned.session.userKey,
        equineId: EQUINE,
      },
      { ok: true, snapshot: claimSnapshot(true) },
    );
    const section = relationClaimModelSection(reconciled.model, EQUINE);
    assert.equal(section?.ownership.statusLabel, 'Solicitud pendiente');
    assert.equal(section?.ownership.canSubmit, false);
    assert.equal(reconciled.model.confirmed.OWNERSHIP, false);
    assert.equal(reconciled.model.confirmed.MANAGEMENT, false);
    assert.equal(
      beginRelationClaimModelSubmit(reconciled.model, 'OWNERSHIP', 'user-a', EQUINE),
      null,
    );
    assert.equal(calls, 1);
  });

  it('shows the open claim and drops only the redundant provisional block', async () => {
    const failed = await driveClaimSubmit(
      readyClaimModel(),
      async () => undefined,
      async () => {
        throw new Error('timeout');
      },
    );
    assert.equal(failed.model.confirmed.OWNERSHIP, true);
    const reconciled = reconcileRelationClaimSnapshot(
      failed.model,
      {
        requestSeq: failed.model.session.requestSeq,
        userKey: failed.model.session.userKey,
        equineId: EQUINE,
      },
      { ok: true, snapshot: claimSnapshot(true) },
    );
    assert.equal(
      relationClaimModelSection(reconciled.model, EQUINE)?.ownership.statusLabel,
      'Solicitud pendiente',
    );
    assert.equal(reconciled.model.confirmed.OWNERSHIP, false);
    assert.equal(
      beginRelationClaimModelSubmit(reconciled.model, 'OWNERSHIP', 'user-a', EQUINE),
      null,
    );
  });

  it('blocks a timed-out mutation when the snapshot shows the open claim', async () => {
    let calls = 0;
    const first = await driveClaimSubmit(
      readyClaimModel(),
      async () => {
        calls += 1;
        throw new Error('Network request failed');
      },
      async () => claimSnapshot(true),
    );
    assert.equal(first.model.pending.OWNERSHIP, false);
    assert.equal(
      relationClaimModelSection(first.model, EQUINE)?.ownership.statusLabel,
      'Solicitud pendiente',
    );
    assert.equal(relationClaimModelSection(first.model, EQUINE)?.ownership.canSubmit, false);
    const second = await driveClaimSubmit(
      first.model,
      async () => {
        calls += 1;
      },
      async () => claimSnapshot(true),
    );
    assert.equal(second.sent, false);
    assert.equal(calls, 1);
  });

  it('stays blocked when a timeout and the snapshot read both fail', async () => {
    let calls = 0;
    const first = await driveClaimSubmit(
      readyClaimModel(),
      async (box) => {
        calls += 1;
        box.model = blurRelationClaimModel(box.model);
        throw new Error('timeout');
      },
      async () => {
        throw new Error('timeout');
      },
    );
    assert.equal(first.model.confirmed.OWNERSHIP, true);
    assert.equal(first.model.pending.OWNERSHIP, true);
    assert.equal(first.model.session.notice, null);
    assert.equal(first.model.session.errorMessage, CLAIM_RECONCILE_ERROR);
    const returned = focusRelationClaimModel(first.model);
    assert.equal(relationClaimModelSection(returned, EQUINE)?.ownership.canSubmit, false);
    const second = await driveClaimSubmit(
      returned,
      async () => {
        calls += 1;
      },
      async () => claimSnapshot(false),
    );
    assert.equal(second.sent, false);
    assert.equal(calls, 1);
  });

  it('retries only after a valid snapshot shows no open claim', async () => {
    let calls = 0;
    const failed = await driveClaimSubmit(
      readyClaimModel(),
      async () => {
        calls += 1;
        throw new Error('Network request failed');
      },
      async () => claimSnapshot(false),
    );
    assert.equal(failed.model.confirmed.OWNERSHIP, false);
    assert.equal(failed.model.pending.OWNERSHIP, false);
    const retry = await driveClaimSubmit(
      failed.model,
      async () => {
        calls += 1;
      },
      async () => claimSnapshot(true),
    );
    assert.equal(retry.sent, true);
    assert.equal(calls, 2);
    const extra = await driveClaimSubmit(
      retry.model,
      async () => {
        calls += 1;
      },
      async () => claimSnapshot(true),
    );
    assert.equal(extra.sent, false);
    assert.equal(calls, 2);
  });

  it('retries a local failure that happens before the RPC', async () => {
    let calls = 0;
    const failed = await driveClaimSubmit(
      readyClaimModel(),
      async () => {
        throw new RelationClaimUnavailable();
      },
      async () => {
        calls += 1;
        return claimSnapshot(true);
      },
    );
    assert.equal(calls, 0);
    assert.equal(failed.model.confirmed.OWNERSHIP, false);
    assert.equal(failed.model.pending.OWNERSHIP, false);
    assert.equal(failed.model.session.errorMessage, 'No se ha podido registrar la reclamación.');
    const retry = await driveClaimSubmit(
      failed.model,
      async () => {
        calls += 1;
      },
      async () => claimSnapshot(true),
    );
    assert.equal(retry.sent, true);
    assert.equal(calls, 1);
  });

  it('allows exactly one retry when the server rejects with 42501', async () => {
    let calls = 0;
    let reads = 0;
    const failed = await driveClaimSubmit(
      readyClaimModel(),
      async () => {
        calls += 1;
        throw Object.assign(new Error('Verification request is not available'), { code: '42501' });
      },
      async () => {
        reads += 1;
        return claimSnapshot(true);
      },
    );
    assert.equal(reads, 0);
    assert.equal(failed.model.confirmed.OWNERSHIP, false);
    assert.equal(failed.model.pending.OWNERSHIP, false);
    assert.equal(
      failed.model.session.errorMessage,
      'No se pudo completar la verificación. Inténtalo de nuevo.',
    );
    const retry = await driveClaimSubmit(
      failed.model,
      async () => {
        calls += 1;
      },
      async () => claimSnapshot(true),
    );
    assert.equal(retry.sent, true);
    assert.equal(calls, 2);
    const extra = await driveClaimSubmit(
      retry.model,
      async () => {
        calls += 1;
      },
      async () => claimSnapshot(true),
    );
    assert.equal(extra.sent, false);
    assert.equal(calls, 2);
  });

  it('fails closed when the mutation response cannot be read', async () => {
    let calls = 0;
    const ambiguous = await driveClaimSubmit(
      readyClaimModel(),
      async () => {
        calls += 1;
        throw new VerificationResponseError();
      },
      async () => {
        throw new Error('timeout');
      },
    );
    assert.equal(ambiguous.model.confirmed.OWNERSHIP, true);
    assert.equal(ambiguous.model.pending.OWNERSHIP, true);
    assert.equal(ambiguous.model.session.notice, null);
    assert.equal(ambiguous.model.session.errorMessage, CLAIM_RECONCILE_ERROR);
    const second = await driveClaimSubmit(
      ambiguous.model,
      async () => {
        calls += 1;
      },
      async () => claimSnapshot(true),
    );
    assert.equal(second.sent, false);
    assert.equal(calls, 1);
  });
});

describe('verification account switch', () => {
  it('clears the previous account before a late response can apply', () => {
    const started = createVerificationSession('user-a');
    const switched = switchVerificationUser(
      { ...started, requestSeq: 4, pendingSnapshot: null, pendingError: 'old' },
      'user-b',
    );
    assert.equal(switched.userKey, 'user-b');
    assert.equal(switched.pendingError, null);
    assert.equal(switched.submit.inFlight, false);
    assert.equal(
      shouldApplyVerificationResult(4, switched.requestSeq, true, 'user-a', switched.userKey),
      false,
    );
  });
});
