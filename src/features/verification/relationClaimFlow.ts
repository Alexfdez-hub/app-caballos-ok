import {
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
  switchRelationClaimContext,
  type RelationClaimFlight,
  type RelationClaimRefresh,
  type RelationClaimRequest,
  type RelationClaimSession,
} from './relationClaimSession.ts';

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
      },
    };
  }

  const equineId = finished.session.equineId;
  let confirmed = model.confirmed;
  if (equineId) {
    const section = presentRelationClaims({
      equineId,
      ownerships: result.snapshot.ownerships,
      assignments: result.snapshot.assignments,
      ownershipClaims: result.snapshot.ownershipClaims,
      managementClaims: result.snapshot.managementClaims,
      trustRows: result.snapshot.trustRows,
    });
    confirmed = {
      OWNERSHIP: model.confirmed.OWNERSHIP && section.ownership.canSubmit,
      MANAGEMENT: model.confirmed.MANAGEMENT && section.management.canSubmit,
    };
  }

  return {
    paint: true,
    model: {
      session: finished.session,
      held: result.snapshot,
      visible: result.snapshot,
      confirmed,
    },
  };
}
