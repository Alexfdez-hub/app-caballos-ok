import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { useAuth } from '../auth/useAuth';
import {
  CLAIM_RECORDED_NOTICE,
  presentRelationClaims,
  type RelationClaimSection,
} from './relationClaims';
import {
  loadRelationClaimSnapshot,
  submitManagementClaim,
  submitOwnershipClaim,
  type RelationClaimSnapshot,
} from './relationClaimService';
import {
  beginRelationClaimRefresh,
  beginRelationClaimSubmit,
  createRelationClaimSession,
  finishRelationClaimRefresh,
  markRelationClaimsBlurred,
  markRelationClaimsFocused,
  relationClaimFlight,
  settleRelationClaimSubmit,
  shouldResetRelationClaims,
  switchRelationClaimContext,
} from './relationClaimSession';
import { userFacingVerificationMessage } from './verificationErrors';

const EMPTY_FLIGHT = {
  inFlight: false,
  notice: null as string | null,
  errorMessage: null as string | null,
};

export function useRelationClaims(equineId: string) {
  const { session } = useAuth();
  const userKey = session?.user.id ?? null;
  const sessionRef = useRef(createRelationClaimSession(userKey));
  const [snapshot, setSnapshot] = useState<RelationClaimSnapshot | null>(null);
  const [isLoading, setIsLoading] = useState(Boolean(userKey));
  const [flight, setFlight] = useState(EMPTY_FLIGHT);

  if (shouldResetRelationClaims(sessionRef.current, userKey, equineId)) {
    sessionRef.current = switchRelationClaimContext(
      sessionRef.current,
      userKey,
      equineId,
    );
    setSnapshot(null);
    setFlight(EMPTY_FLIGHT);
    setIsLoading(Boolean(userKey));
  }

  const refresh = useCallback(async () => {
    if (!userKey) {
      setSnapshot(null);
      setFlight(EMPTY_FLIGHT);
      setIsLoading(false);
      return;
    }

    const started = beginRelationClaimRefresh(sessionRef.current);
    if (!started) {
      setSnapshot(null);
      setFlight(EMPTY_FLIGHT);
      setIsLoading(false);
      return;
    }

    sessionRef.current = started.session;
    const refresh = started.refresh;
    setIsLoading(true);

    try {
      const next = await loadRelationClaimSnapshot();
      const finished = finishRelationClaimRefresh(sessionRef.current, refresh, {
        ok: true,
      });
      sessionRef.current = finished.session;
      if (!finished.paint) {
        return;
      }
      setSnapshot(next);
      setFlight(relationClaimFlight(finished.session));
    } catch (error) {
      const finished = finishRelationClaimRefresh(sessionRef.current, refresh, {
        ok: false,
        errorMessage: userFacingVerificationMessage(error),
      });
      sessionRef.current = finished.session;
      if (!finished.paint) {
        return;
      }
      if (!finished.session.inFlight) {
        setSnapshot(null);
      }
      setFlight(relationClaimFlight(finished.session));
    } finally {
      if (
        refresh.refreshSeq === sessionRef.current.refreshSeq &&
        refresh.userKey === sessionRef.current.userKey &&
        refresh.equineId === sessionRef.current.equineId &&
        sessionRef.current.screenActive
      ) {
        setIsLoading(false);
      }
    }
  }, [equineId, userKey]);

  const submit = useCallback(
    async (kind: 'OWNERSHIP' | 'MANAGEMENT') => {
      if (!snapshot || !userKey) {
        return;
      }

      const section = presentRelationClaims({ equineId, ...snapshot });
      const payload =
        kind === 'OWNERSHIP'
          ? section.ownership.ownershipPayload
          : section.management.managementPayload;
      if (!payload) {
        return;
      }

      const started = beginRelationClaimSubmit(
        sessionRef.current,
        userKey,
        equineId,
      );
      if (!started) {
        return;
      }

      sessionRef.current = started.session;
      setFlight({ inFlight: true, notice: null, errorMessage: null });

      try {
        if (kind === 'OWNERSHIP' && started.session) {
          await submitOwnershipClaim(section.ownership.ownershipPayload!);
        } else {
          await submitManagementClaim(section.management.managementPayload!);
        }
        const next = await loadRelationClaimSnapshot();
        const settled = settleRelationClaimSubmit(sessionRef.current, started.request, {
          ok: true,
          notice: CLAIM_RECORDED_NOTICE,
        });
        sessionRef.current = settled.session;
        if (settled.apply) {
          setSnapshot(next);
          setFlight(relationClaimFlight(settled.session));
        }
      } catch (error) {
        const message = userFacingVerificationMessage(error);
        const settled = settleRelationClaimSubmit(sessionRef.current, started.request, {
          ok: false,
          errorMessage: message,
        });
        sessionRef.current = settled.session;
        if (settled.apply) {
          setFlight(relationClaimFlight(settled.session));
        }
      }
    },
    [equineId, snapshot, userKey],
  );

  useFocusEffect(
    useCallback(() => {
      sessionRef.current = markRelationClaimsFocused(sessionRef.current);
      setFlight(relationClaimFlight(sessionRef.current));
      void refresh();
      return () => {
        sessionRef.current = markRelationClaimsBlurred(sessionRef.current);
      };
    }, [refresh]),
  );

  const section: RelationClaimSection | null = snapshot
    ? presentRelationClaims({ equineId, ...snapshot })
    : null;

  return {
    hasSession: userKey !== null,
    isLoading,
    isSubmitting: flight.inFlight,
    notice: flight.notice,
    errorMessage: flight.errorMessage,
    section,
    refresh,
    submitOwnership: () => submit('OWNERSHIP'),
    submitManagement: () => submit('MANAGEMENT'),
  };
}
