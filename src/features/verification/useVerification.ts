import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { shouldApplyCenterMembershipRefresh } from '../centers/membershipRefresh';
import { useAuth } from '../auth/useAuth';
import {
  finishIdentitySubmit,
  identitySubmitSucceeded,
  presentManagement,
  presentOwnerships,
  presentSpainIdentity,
  reloadAfterSpainIdentityRequest,
  startIdentitySubmit,
  type SubmitState,
} from './presentation';
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
  const [submitState, setSubmitState] = useState<SubmitState>({
    inFlight: false,
    notice: null,
  });
  const requestSeqRef = useRef(0);
  const isScreenActiveRef = useRef(false);
  const submitStateRef = useRef(submitState);
  submitStateRef.current = submitState;

  const refresh = useCallback(async () => {
    if (!session) {
      setSnapshot(null);
      setIsLoading(false);
      setErrorMessage(null);
      return;
    }

    const requestSeq = requestSeqRef.current + 1;
    requestSeqRef.current = requestSeq;
    setIsLoading(true);
    setErrorMessage(null);

    try {
      const nextSnapshot = await loadMyVerification();
      if (
        !shouldApplyCenterMembershipRefresh(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
        )
      ) {
        return;
      }
      setSnapshot(nextSnapshot);
    } catch (error) {
      if (
        !shouldApplyCenterMembershipRefresh(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
        )
      ) {
        return;
      }
      setSnapshot(null);
      setErrorMessage(userFacingVerificationMessage(error));
    } finally {
      if (
        shouldApplyCenterMembershipRefresh(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
        )
      ) {
        setIsLoading(false);
      }
    }
  }, [session]);

  const requestSpainIdentity = useCallback(async () => {
    const started = startIdentitySubmit(submitStateRef.current);
    if (!started || !session) {
      return;
    }

    submitStateRef.current = started;
    setSubmitState(started);
    setErrorMessage(null);

    try {
      const nextSnapshot = await reloadAfterSpainIdentityRequest({
        submit: submitSpainIdentityCase,
        load: loadMyVerification,
      });
      if (!isScreenActiveRef.current) {
        return;
      }
      setSnapshot(nextSnapshot);
      const succeeded = identitySubmitSucceeded();
      submitStateRef.current = succeeded;
      setSubmitState(succeeded);
    } catch (error) {
      if (!isScreenActiveRef.current) {
        return;
      }
      const failed = finishIdentitySubmit({ inFlight: false, notice: null });
      submitStateRef.current = failed;
      setSubmitState(failed);
      setErrorMessage(userFacingVerificationMessage(error));
    }
  }, [session]);

  useFocusEffect(
    useCallback(() => {
      isScreenActiveRef.current = true;
      void refresh();
      return () => {
        isScreenActiveRef.current = false;
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
