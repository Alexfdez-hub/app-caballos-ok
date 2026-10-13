import {
  CLAIM_RECONCILE_ERROR,
  presentRelationClaims,
  type RelationClaimSection,
} from './relationClaims.ts';
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
  shouldSettleRelationClaimResult,
  switchRelationClaimContext,
  type RelationClaimFlight,
  type RelationClaimRefresh,
  type RelationClaimRequest,
  type RelationClaimSession,
} from './relationClaimSession.ts';
import { userFacingVerificationMessage } from './verificationErrors.ts';

export type RelationClaimKind = 'OWNERSHIP' | 'MANAGEMENT';

export type ConfirmedRelationClaims = {
  OWNERSHIP: boolean;
  MANAGEMENT: boolean;
};

export type RelationClaimModel = {
  session: RelationClaimSession;
  held: RelationClaimSnapshot | null;
  visible: RelationClaimSnapshot | null;
  confirmed: ConfirmedRelationClaims;
  /** Ambiguous mutation. A valid snapshot with no open claim may release it. */
  pending: ConfirmedRelationClaims;
};

const noneConfirmed = (): ConfirmedRelationClaims => ({
  OWNERSHIP: false,
  MANAGEMENT: false,
});

export function createRelationClaimModel(
  userKey: string | null,
  equineId: string,
): RelationClaimModel {
  return {
    session: switchRelationClaimContext(
      createRelationClaimSession(userKey),
      userKey,
      equineId,
    ),
    held: null,
    visible: null,
    confirmed: noneConfirmed(),
    pending: noneConfirmed(),
  };
}

export function relationClaimModelFlight(model: RelationClaimModel): RelationClaimFlight {
  return relationClaimFlight(model.session);
}

function blockAction(
  action: RelationClaimSection['ownership'],
): RelationClaimSection['ownership'] {
  return {
    ...action,
    canSubmit: false,
    ownershipPayload: null,
    managementPayload: null,
  };
}

/** The section the screen may render. A confirmed submit stays closed. */
export function relationClaimModelSection(
  model: RelationClaimModel,
  equineId: string,
): RelationClaimSection | null {
  if (!model.visible) return null;
  const section = presentRelationClaims({
    equineId,
    ownerships: model.visible.ownerships,
    assignments: model.visible.assignments,
    ownershipClaims: model.visible.ownershipClaims,
    managementClaims: model.visible.managementClaims,
    trustRows: model.visible.trustRows,
  });
  return {
    ownership: model.confirmed.OWNERSHIP ? blockAction(section.ownership) : section.ownership,
    management: model.confirmed.MANAGEMENT
      ? blockAction(section.management)
      : section.management,
  };
}

export function switchRelationClaimModel(
  model: RelationClaimModel,
  userKey: string | null,
  equineId: string,
): RelationClaimModel {
  return {
    session: switchRelationClaimContext(model.session, userKey, equineId),
    held: null,
    visible: null,
    confirmed: noneConfirmed(),
    pending: noneConfirmed(),
  };
}

export function focusRelationClaimModel(model: RelationClaimModel): RelationClaimModel {
  return {
    ...model,
    session: markRelationClaimsFocused(model.session),
    visible: model.held ?? model.visible,
  };
}

export function blurRelationClaimModel(model: RelationClaimModel): RelationClaimModel {
  return { ...model, session: markRelationClaimsBlurred(model.session) };
}

/**
 * Logical gate. A confirmed kind cannot start another request, even when the
 * painted snapshot is still the one from before the submit.
 */
export function beginRelationClaimModelSubmit(
  model: RelationClaimModel,
  kind: RelationClaimKind,
  userKey: string | null,
  equineId: string,
): { model: RelationClaimModel; request: RelationClaimRequest } | null {
  if (model.confirmed[kind]) return null;
  const equineIdOnScreen = model.session.equineId;
  const section = equineIdOnScreen
    ? relationClaimModelSection(model, equineIdOnScreen)
    : null;
  if (!section) return null;
  if (kind === 'OWNERSHIP' && !section.ownership.canSubmit) return null;
  if (kind === 'MANAGEMENT' && !section.management.canSubmit) return null;
  const started = beginRelationClaimSubmit(model.session, userKey, equineId);
  if (!started) return null;
  return {
    model: { ...model, session: started.session },
    request: started.request,
  };
}

export function settleRelationClaimModelSuccess(
  model: RelationClaimModel,
  request: RelationClaimRequest,
  snapshot: RelationClaimSnapshot,
  notice: string,
  kind: RelationClaimKind,
): { model: RelationClaimModel; apply: boolean } {
  const settled = settleRelationClaimSubmit(model.session, request, { ok: true, notice });
  if (settled.session === model.session) return { model, apply: false };
  return {
    apply: settled.apply,
    model: {
      session: settled.session,
      held: snapshot,
      visible: settled.apply ? snapshot : model.visible,
      confirmed: { ...model.confirmed, [kind]: true },
      pending: { ...model.pending, [kind]: false },
    },
  };
}

export function settleRelationClaimModelFailure(
  model: RelationClaimModel,
  request: RelationClaimRequest,
  errorMessage: string,
): { model: RelationClaimModel; apply: boolean } {
  const settled = settleRelationClaimSubmit(model.session, request, {
    ok: false,
    errorMessage,
  });
  if (settled.session === model.session) return { model, apply: false };
  return {
    apply: settled.apply,
    model: { ...model, session: settled.session },
  };
}

export function beginRelationClaimModelRefresh(
  model: RelationClaimModel,
): { model: RelationClaimModel; refresh: RelationClaimRefresh } | null {
  const started = beginRelationClaimRefresh(model.session);
  if (!started) return null;
  return { model: { ...model, session: started.session }, refresh: started.refresh };
}

function anyConfirmed(confirmed: ConfirmedRelationClaims): boolean {
  return confirmed.OWNERSHIP || confirmed.MANAGEMENT;
}

export function finishRelationClaimModelRefresh(
  model: RelationClaimModel,
  refresh: RelationClaimRefresh,
  result:
    | { ok: true; snapshot: RelationClaimSnapshot }
    | { ok: false; errorMessage: string },
): { model: RelationClaimModel; paint: boolean } {
  const finished = finishRelationClaimRefresh(
    model.session,
    refresh,
    result.ok
      ? { ok: true }
      : { ok: false, errorMessage: result.errorMessage },
  );
  if (!finished.paint) return { model, paint: false };

  if (finished.session.inFlight) {
    return { paint: true, model: { ...model, session: finished.session } };
  }

  if (!result.ok) {
    if (anyConfirmed(model.confirmed)) {
      return {
        paint: true,
        model: {
          session: {
            ...finished.session,
            notice: model.session.notice,
            errorMessage: result.errorMessage,
          },
          held: model.held,
          visible: model.held ?? model.visible,
          confirmed: model.confirmed,
          pending: model.pending,
        },
      };
    }
    return {
      paint: true,
      model: {
        session: finished.session,
        held: null,
        visible: null,
        confirmed: noneConfirmed(),
        pending: noneConfirmed(),
      },
    };
  }

  const equineId = finished.session.equineId;
  const holds = equineId
    ? holdsAfterSnapshot(model, equineId, result.snapshot)
    : { confirmed: model.confirmed, pending: model.pending };

  return {
    paint: true,
    model: {
      session: finished.session,
      held: result.snapshot,
      visible: result.snapshot,
      confirmed: holds.confirmed,
      pending: holds.pending,
    },
  };
}

const OPEN_CLAIM_STATES = new Set(['SUBMITTED', 'IN_REVIEW', 'RESUBMITTED']);

function snapshotHasOpenClaim(
  snapshot: RelationClaimSnapshot,
  kind: RelationClaimKind,
  equineId: string,
): boolean {
  const claims = kind === 'OWNERSHIP' ? snapshot.ownershipClaims : snapshot.managementClaims;
  return claims.some(
    (claim) =>
      claim.equineId === equineId &&
      claim.marketCountryCode === 'ES' &&
      OPEN_CLAIM_STATES.has(claim.state),
  );
}

/**
 * An open claim drops the redundant lock because the snapshot itself blocks.
 * A pending lock is released only when that valid snapshot has no open claim.
 * A proven write stays locked if the list still does not show the claim.
 */
function holdsAfterSnapshot(
  model: RelationClaimModel,
  equineId: string,
  snapshot: RelationClaimSnapshot,
): { confirmed: ConfirmedRelationClaims; pending: ConfirmedRelationClaims } {
  const confirmed = { ...model.confirmed };
  const pending = { ...model.pending };
  for (const kind of ['OWNERSHIP', 'MANAGEMENT'] as const) {
    if (!confirmed[kind] && !pending[kind]) continue;
    if (snapshotHasOpenClaim(snapshot, kind, equineId) || pending[kind]) {
      confirmed[kind] = false;
      pending[kind] = false;
    }
  }
  return { confirmed, pending };
}

/**
 * The mutation RPC has already succeeded, or its body could not be read after
 * a possible commit. The kind is blocked before any later snapshot read.
 */
export function acceptRelationClaimMutation(
  model: RelationClaimModel,
  request: RelationClaimRequest,
  kind: RelationClaimKind,
  notice: string,
): { model: RelationClaimModel; apply: boolean; settled: boolean } {
  const settled = settleRelationClaimSubmit(model.session, request, { ok: true, notice });
  if (settled.session === model.session) return { model, apply: false, settled: false };
  const held = model.held ?? model.visible;
  return {
    settled: true,
    apply: settled.apply,
    model: {
      session: settled.session,
      held,
      visible: settled.apply ? held : model.visible,
      confirmed: { ...model.confirmed, [kind]: true },
      pending: { ...model.pending, [kind]: false },
    },
  };
}

/** The snapshot read that follows a confirmed mutation. It never reopens that kind. */
export function reconcileRelationClaimSnapshot(
  model: RelationClaimModel,
  request: RelationClaimRequest,
  result:
    | { ok: true; snapshot: RelationClaimSnapshot }
    | { ok: false; errorMessage?: string },
): { model: RelationClaimModel; apply: boolean; settled: boolean } {
  if (!shouldSettleRelationClaimResult(request, model.session)) {
    return { model, apply: false, settled: false };
  }

  const apply = model.session.screenActive;
  if (!result.ok) {
    const held = model.held ?? model.visible;
    return {
      settled: true,
      apply,
      model: {
      session: {
        ...model.session,
        mutationSeq: model.session.mutationSeq + 1,
        inFlight: false,
        notice: model.session.notice,
        errorMessage: result.errorMessage ?? CLAIM_RECONCILE_ERROR,
      },
        held,
        visible: apply ? held : model.visible,
        confirmed: model.confirmed,
        pending: model.pending,
      },
    };
  }

  const equineId = model.session.equineId;
  const holds = equineId
    ? holdsAfterSnapshot(model, equineId, result.snapshot)
    : { confirmed: model.confirmed, pending: model.pending };
  return {
    settled: true,
    apply,
    model: {
      session: {
        ...model.session,
        mutationSeq: model.session.mutationSeq + 1,
        inFlight: false,
        notice: model.session.notice,
        errorMessage: null,
      },
      held: result.snapshot,
      visible: apply ? result.snapshot : model.visible,
      confirmed: holds.confirmed,
      pending: holds.pending,
    },
  };
}

export class RelationClaimUnavailable extends Error {
  constructor() {
    super('No se ha podido registrar la reclamación.');
    this.name = 'RelationClaimUnavailable';
  }
}

/**
 * SQLSTATE 42501 is the only refusal this RPC returns, and only after the
 * transaction aborts. Receiving it means the insert was not committed.
 * Timeouts, network failures, and every other code stay ambiguous.
 */
export const UNEQUIVOCAL_CLAIM_REJECTION_CODE = '42501';

export function relationClaimMutationDisposition(
  error: unknown,
): 'local' | 'rejected' | 'ambiguous' {
  if (error instanceof RelationClaimUnavailable) return 'local';
  if (!error || typeof error !== 'object' || !('code' in error)) return 'ambiguous';
  return String((error as { code?: unknown }).code) === UNEQUIVOCAL_CLAIM_REJECTION_CODE
    ? 'rejected'
    : 'ambiguous';
}

/** Unknown mutation result. Block the kind until a snapshot proves what was written. */
export function holdRelationClaimForReconciliation(
  model: RelationClaimModel,
  request: RelationClaimRequest,
  kind: RelationClaimKind,
): { model: RelationClaimModel; apply: boolean; settled: boolean } {
  if (!shouldSettleRelationClaimResult(request, model.session)) {
    return { model, apply: false, settled: false };
  }
  const apply = model.session.screenActive;
  const held = model.held ?? model.visible;
  return {
    settled: true,
    apply,
    model: {
      session: {
        ...model.session,
        mutationSeq: model.session.mutationSeq + 1,
        inFlight: false,
        notice: model.session.notice,
        errorMessage: null,
      },
      held,
      visible: apply ? held : model.visible,
      confirmed: { ...model.confirmed, [kind]: true },
      pending: { ...model.pending, [kind]: true },
    },
  };
}

/**
 * Confirms the mutation before reading the snapshot. A failed read keeps the
 * kind blocked. Only a rejection before confirmation releases a retry.
 */
export async function attemptRelationClaimSubmit(input: {
  model: RelationClaimModel;
  kind: RelationClaimKind;
  userKey: string | null;
  equineId: string;
  notice: string;
  mutate: () => Promise<void>;
  loadSnapshot: () => Promise<RelationClaimSnapshot>;
  readModel?: () => RelationClaimModel;
  writeModel?: (model: RelationClaimModel) => void;
}): Promise<{ model: RelationClaimModel; sent: boolean; confirmed: boolean }> {
  let current = input.readModel ? input.readModel() : input.model;
  const read = input.readModel ?? (() => current);
  const started = beginRelationClaimModelSubmit(
    current,
    input.kind,
    input.userKey,
    input.equineId,
  );
  if (!started) return { model: current, sent: false, confirmed: false };

  current = started.model;
  input.writeModel?.(current);

  let ambiguous = false;
  try {
    await input.mutate();
  } catch (error) {
    current = read();
    const disposition = relationClaimMutationDisposition(error);
    if (disposition === 'local' || disposition === 'rejected') {
      const message =
        error instanceof RelationClaimUnavailable
          ? error.message
          : userFacingVerificationMessage(error);
      const failed = settleRelationClaimModelFailure(current, started.request, message);
      input.writeModel?.(failed.model);
      return { model: failed.model, sent: true, confirmed: false };
    }
    const held = holdRelationClaimForReconciliation(current, started.request, input.kind);
    if (!held.settled) {
      input.writeModel?.(held.model);
      return { model: held.model, sent: true, confirmed: false };
    }
    current = held.model;
    input.writeModel?.(current);
    ambiguous = true;
  }

  if (!ambiguous) {
    current = read();
    const accepted = acceptRelationClaimMutation(
      current,
      started.request,
      input.kind,
      input.notice,
    );
    if (!accepted.settled) {
      input.writeModel?.(accepted.model);
      return { model: accepted.model, sent: true, confirmed: false };
    }
    current = accepted.model;
    input.writeModel?.(current);
  }

  try {
    const snapshot = await input.loadSnapshot();
    current = read();
    const reconciled = reconcileRelationClaimSnapshot(current, started.request, {
      ok: true,
      snapshot,
    });
    input.writeModel?.(reconciled.model);
    return { model: reconciled.model, sent: true, confirmed: true };
  } catch {
    current = read();
    const reconciled = reconcileRelationClaimSnapshot(current, started.request, {
      ok: false,
      errorMessage: CLAIM_RECONCILE_ERROR,
    });
    input.writeModel?.(reconciled.model);
    return { model: reconciled.model, sent: true, confirmed: true };
  }
}
