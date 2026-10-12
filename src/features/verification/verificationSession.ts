import type { SubmitState } from './presentation';
import type { VerificationSnapshot } from './types';

export type VerificationSession = {
  requestSeq: number;
  screenActive: boolean;
  userKey: string | null;
  submit: SubmitState;
  pendingSnapshot: VerificationSnapshot | null;
  pendingError: string | null;
};

export function createVerificationSession(
  userKey: string | null = null,
): VerificationSession {
  return {
    requestSeq: 0,
    screenActive: false,
    userKey,
    submit: { inFlight: false, notice: null },
    pendingSnapshot: null,
    pendingError: null,
  };
}

export function shouldResetVerificationUser(
  previousKey: string | null,
  nextKey: string | null,
): boolean {
  return previousKey !== nextKey;
}

export function switchVerificationUser(
  session: VerificationSession,
  userKey: string | null,
): VerificationSession {
  return {
    requestSeq: session.requestSeq + 1,
    screenActive: session.screenActive,
    userKey,
    submit: { inFlight: false, notice: null },
    pendingSnapshot: null,
    pendingError: null,
  };
}

export function shouldApplyVerificationResult(
  requestSeq: number,
  latestSeq: number,
  screenActive: boolean,
  requestUserKey: string | null = null,
  sessionUserKey: string | null = null,
): boolean {
  return (
    screenActive &&
    requestSeq === latestSeq &&
    requestUserKey === sessionUserKey
  );
}

export function markVerificationFocused(
  session: VerificationSession,
): VerificationSession {
  return { ...session, screenActive: true };
}

export function markVerificationBlurred(
  session: VerificationSession,
): VerificationSession {
  return { ...session, screenActive: false };
}

export function beginVerificationRefresh(
  session: VerificationSession,
): { session: VerificationSession; requestSeq: number } | null {
  if (session.submit.inFlight) {
    return null;
  }

  const requestSeq = session.requestSeq + 1;
  return {
    requestSeq,
    session: { ...session, requestSeq, userKey: session.userKey },
  };
}

export function beginSpainIdentitySubmit(
  session: VerificationSession,
): VerificationSession | null {
  if (session.submit.inFlight) {
    return null;
  }

  return {
    ...session,
    requestSeq: session.requestSeq + 1,
    pendingError: null,
    submit: { inFlight: true, notice: null },
  };
}

export function settleSpainIdentitySubmit(
  session: VerificationSession,
  result:
    | { ok: true; snapshot: VerificationSnapshot; notice: string }
    | { ok: false; errorMessage: string },
): { session: VerificationSession; apply: boolean } {
  const next: VerificationSession = result.ok
    ? {
        ...session,
        pendingSnapshot: result.snapshot,
        pendingError: null,
        submit: { inFlight: false, notice: result.notice },
      }
    : {
        ...session,
        pendingError: result.errorMessage,
        submit: { inFlight: false, notice: null },
      };

  return { session: next, apply: session.screenActive };
}
