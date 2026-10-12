export type RelationClaimRequest = {
  requestSeq: number;
  userKey: string | null;
  equineId: string;
};

export type RelationClaimSession = {
  requestSeq: number;
  userKey: string | null;
  equineId: string | null;
  screenActive: boolean;
  inFlight: boolean;
  notice: string | null;
  errorMessage: string | null;
};

export function createRelationClaimSession(
  userKey: string | null = null,
): RelationClaimSession {
  return {
    requestSeq: 0,
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
    userKey,
    equineId,
    screenActive: session.screenActive,
    inFlight: false,
    notice: null,
    errorMessage: null,
  };
}

export function shouldApplyRelationClaimResult(
  request: RelationClaimRequest,
  session: RelationClaimSession,
): boolean {
  return (
    session.screenActive &&
    request.requestSeq === session.requestSeq &&
    request.userKey === session.userKey &&
    request.equineId === session.equineId
  );
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
  const apply = shouldApplyRelationClaimResult(request, session);
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

  return { session: next, apply };
}
