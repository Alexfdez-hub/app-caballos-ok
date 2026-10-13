export type RelationClaimRequest = {
  requestSeq: number;
  userKey: string | null;
  equineId: string;
};

export type RelationClaimSession = {
  requestSeq: number;
  refreshSeq: number;
  userKey: string | null;
  equineId: string | null;
  screenActive: boolean;
  inFlight: boolean;
  notice: string | null;
  errorMessage: string | null;
};

export type RelationClaimFlight = {
  inFlight: boolean;
  notice: string | null;
  errorMessage: string | null;
};

export type RelationClaimRefresh = {
  refreshSeq: number;
  userKey: string | null;
  equineId: string;
};

export function createRelationClaimSession(
  userKey: string | null = null,
): RelationClaimSession {
  return {
    requestSeq: 0,
    refreshSeq: 0,
    userKey,
    equineId: null,
    screenActive: false,
    inFlight: false,
    notice: null,
    errorMessage: null,
  };
}

export function shouldResetRelationClaims(
  session: RelationClaimSession,
  userKey: string | null,
  equineId: string,
): boolean {
  return session.userKey !== userKey || session.equineId !== equineId;
}

export function switchRelationClaimContext(
  session: RelationClaimSession,
  userKey: string | null,
  equineId: string,
): RelationClaimSession {
  return {
    requestSeq: session.requestSeq + 1,
    refreshSeq: session.refreshSeq,
    userKey,
    equineId,
    screenActive: session.screenActive,
    inFlight: false,
    notice: null,
    errorMessage: null,
  };
}

export function shouldSettleRelationClaimResult(
  request: RelationClaimRequest,
  session: RelationClaimSession,
): boolean {
  return (
    request.requestSeq === session.requestSeq &&
    request.userKey === session.userKey &&
    request.equineId === session.equineId
  );
}

export function shouldApplyRelationClaimResult(
  request: RelationClaimRequest,
  session: RelationClaimSession,
): boolean {
  return (
    session.screenActive &&
    shouldSettleRelationClaimResult(request, session)
  );
}

export function relationClaimFlight(
  session: RelationClaimSession,
): RelationClaimFlight {
  return {
    inFlight: session.inFlight,
    notice: session.notice,
    errorMessage: session.errorMessage,
  };
}

export function markRelationClaimsFocused(
  session: RelationClaimSession,
): RelationClaimSession {
  return { ...session, screenActive: true };
}

export function markRelationClaimsBlurred(
  session: RelationClaimSession,
): RelationClaimSession {
  return { ...session, screenActive: false };
}

export function beginRelationClaimSubmit(
  session: RelationClaimSession,
  userKey: string | null,
  equineId: string,
): { session: RelationClaimSession; request: RelationClaimRequest } | null {
  if (session.inFlight || session.userKey !== userKey || session.equineId !== equineId) {
    return null;
  }

  const requestSeq = session.requestSeq + 1;
  const request = { requestSeq, userKey, equineId };
  return {
    request,
    session: {
      ...session,
      requestSeq,
      userKey,
      equineId,
      inFlight: true,
      notice: null,
      errorMessage: null,
    },
  };
}

export function settleRelationClaimSubmit(
  session: RelationClaimSession,
  request: RelationClaimRequest,
  result: { ok: true; notice: string } | { ok: false; errorMessage: string },
): { session: RelationClaimSession; apply: boolean } {
  if (!shouldSettleRelationClaimResult(request, session)) {
    return { session, apply: false };
  }

  const next: RelationClaimSession = result.ok
    ? {
        ...session,
        inFlight: false,
        notice: result.notice,
        errorMessage: null,
      }
    : {
        ...session,
        inFlight: false,
        notice: null,
        errorMessage: result.errorMessage,
      };

  return { session: next, apply: session.screenActive };
}

export function beginRelationClaimRefresh(
  session: RelationClaimSession,
): { session: RelationClaimSession; refresh: RelationClaimRefresh } | null {
  if (!session.userKey || !session.equineId) {
    return null;
  }

  const refreshSeq = session.refreshSeq + 1;
  const refresh = {
    refreshSeq,
    userKey: session.userKey,
    equineId: session.equineId,
  };
  return {
    refresh,
    session: { ...session, refreshSeq },
  };
}

export function finishRelationClaimRefresh(
  session: RelationClaimSession,
  refresh: RelationClaimRefresh,
  result: { ok: true } | { ok: false; errorMessage: string },
): { session: RelationClaimSession; paint: boolean } {
  const sameContext =
    refresh.refreshSeq === session.refreshSeq &&
    refresh.userKey === session.userKey &&
    refresh.equineId === session.equineId;
  if (!sameContext || !session.screenActive) {
    return { session, paint: false };
  }

  if (!result.ok && !session.inFlight) {
    return {
      paint: true,
      session: {
        ...session,
        inFlight: false,
        notice: null,
        errorMessage: result.errorMessage,
      },
    };
  }

  if (result.ok && !session.inFlight) {
    return {
      paint: true,
      session: { ...session, errorMessage: null },
    };
  }

  return { session, paint: true };
}
