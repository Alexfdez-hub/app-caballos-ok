import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { useAuth } from '../auth/useAuth';
import {
  identitySubmitSucceeded,
  presentManagement,
  presentOwnerships,
  presentSpainIdentity,
  reloadAfterSpainIdentityRequest,
} from './presentation';
import {
  beginSpainIdentitySubmit,
  beginVerificationRefresh,
  createVerificationSession,
  markVerificationBlurred,
  markVerificationFocused,
  settleSpainIdentitySubmit,
  shouldApplyVerificationResult,
} from './verificationSession';
import { userFacingVerificationMessage } from './verificationErrors';
import {
  loadMyVerification,
  submitSpainIdentityCase,
} from './verificationService';
import type {
  EquineRelationView,
  SpainIdentityView,
  VerificationSnapshot,
} from './types';

const EMPTY_SPAIN: SpainIdentityView = {
  marketLabel: 'España',
  status: 'UNAVAILABLE',
  statusLabel: 'No disponible',
  canRequest: false,
};

export function useVerification() {
  const { session } = useAuth();
  const [snapshot, setSnapshot] = useState<VerificationSnapshot | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [submitState, setSubmitState] = useState(createVerificationSession().submit);
  const sessionRef = useRef(createVerificationSession());

  const refresh = useCallback(async () => {
    if (!session) {
      setSnapshot(null);
      setIsLoading(false);
      setErrorMessage(null);
      return;
    }

    const started = beginVerificationRefresh(sessionRef.current);
    if (!started) {
      return;
    }

    sessionRef.current = started.session;
    const requestSeq = started.requestSeq;
    setIsLoading(true);
    setErrorMessage(null);

    try {
      const nextSnapshot = await loadMyVerification();
      if (
        !shouldApplyVerificationResult(
          requestSeq,
          sessionRef.current.requestSeq,
          sessionRef.current.screenActive,
        )
      ) {
        return;
      }
      sessionRef.current = {
        ...sessionRef.current,
        pendingSnapshot: nextSnapshot,
        pendingError: null,
      };
      setSnapshot(nextSnapshot);
    } catch (error) {
      if (
        !shouldApplyVerificationResult(
          requestSeq,
          sessionRef.current.requestSeq,
          sessionRef.current.screenActive,
        )
      ) {
        return;
      }
      const message = userFacingVerificationMessage(error);
      sessionRef.current = {
        ...sessionRef.current,
        pendingSnapshot: null,
        pendingError: message,
      };
      setSnapshot(null);
      setErrorMessage(message);
    } finally {
      if (
        shouldApplyVerificationResult(
          requestSeq,
          sessionRef.current.requestSeq,
          sessionRef.current.screenActive,
        )
      ) {
        setIsLoading(false);
      }
    }
  }, [session]);

  const requestSpainIdentity = useCallback(async () => {
    const started = beginSpainIdentitySubmit(sessionRef.current);
    if (!started || !session) {
      return;
    }

    sessionRef.current = started;
    if (started.screenActive) {
      setSubmitState(started.submit);
    }
    setErrorMessage(null);

    try {
      const nextSnapshot = await reloadAfterSpainIdentityRequest({
        submit: submitSpainIdentityCase,
        load: loadMyVerification,
      });
      const settled = settleSpainIdentitySubmit(sessionRef.current, {
        ok: true,
        snapshot: nextSnapshot,
        notice: identitySubmitSucceeded().notice ?? '',
      });
      sessionRef.current = settled.session;
      if (settled.apply) {
        setSnapshot(nextSnapshot);
        setSubmitState(settled.session.submit);
        setErrorMessage(null);
      }
    } catch (error) {
      const message = userFacingVerificationMessage(error);
      const settled = settleSpainIdentitySubmit(sessionRef.current, {
        ok: false,
        errorMessage: message,
      });
      sessionRef.current = settled.session;
      if (settled.apply) {
        setSubmitState(settled.session.submit);
        setErrorMessage(message);
      }
    }
  }, [session]);

  useFocusEffect(
    useCallback(() => {
      sessionRef.current = markVerificationFocused(sessionRef.current);
      setSubmitState(sessionRef.current.submit);
      if (sessionRef.current.pendingSnapshot) {
        setSnapshot(sessionRef.current.pendingSnapshot);
      }
      setErrorMessage(sessionRef.current.pendingError);
      void refresh();
      return () => {
        sessionRef.current = markVerificationBlurred(sessionRef.current);
      };
    }, [refresh]),
  );

  const spain = snapshot ? presentSpainIdentity(snapshot) : EMPTY_SPAIN;
  const ownerships: EquineRelationView[] = snapshot
    ? presentOwnerships(snapshot)
    : [];
  const management: EquineRelationView[] = snapshot
    ? presentManagement(snapshot)
    : [];

  return {
    hasSession: Boolean(session),
    isLoading,
    errorMessage,
    notice: submitState.notice,
    isSubmitting: submitState.inFlight,
    spain,
    ownerships,
    management,
    refresh,
    requestSpainIdentity,
  };
}
