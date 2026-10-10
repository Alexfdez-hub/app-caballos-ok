export type ReviewRequest = {
  requestSeq: number;
  userKey: string | null;
};

export type ReviewPilotSession = {
  requestSeq: number;
  screenActive: boolean;
  userKey: string | null;
  loading: boolean;
};

export function createReviewPilotSession(
  userKey: string | null = null,
): ReviewPilotSession {
  return {
    requestSeq: 0,
    screenActive: false,
    userKey,
    loading: false,
  };
}

export function reviewUserKey(userId: string | null | undefined): string | null {
  return userId ?? null;
}

export function shouldResetReview(
  previousKey: string | null,
  nextKey: string | null,
): boolean {
  return previousKey !== nextKey;
}

export function switchReviewUser(
  session: ReviewPilotSession,
  userKey: string | null,
): ReviewPilotSession {
  return {
    ...session,
    userKey,
    loading: false,
  };
}

export function shouldApplyReviewResult(
  request: ReviewRequest,
  session: ReviewPilotSession,
): boolean {
  return (
    session.screenActive &&
    request.requestSeq === session.requestSeq &&
    request.userKey === session.userKey
  );
}

export function markReviewFocused(
  session: ReviewPilotSession,
): ReviewPilotSession {
  return { ...session, screenActive: true };
}

export function markReviewBlurred(
  session: ReviewPilotSession,
): ReviewPilotSession {
  return { ...session, screenActive: false, loading: false };
}

export function beginReviewLoad(
  session: ReviewPilotSession,
  userKey: string | null,
): { session: ReviewPilotSession; request: ReviewRequest } {
  const requestSeq = session.requestSeq + 1;
  const request = { requestSeq, userKey };

  return {
    request,
    session: {
      ...session,
      requestSeq,
      userKey,
      loading: true,
    },
  };
}
