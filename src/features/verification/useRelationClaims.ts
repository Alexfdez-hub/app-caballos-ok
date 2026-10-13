import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { useAuth } from '../auth/useAuth';
import { CLAIM_RECORDED_NOTICE, type RelationClaimSection } from './relationClaims';
import {
  loadRelationClaimSnapshot,
  submitManagementClaim,
  submitOwnershipClaim,
  type RelationClaimSnapshot,
} from './relationClaimService';
import {
  attemptRelationClaimSubmit,
  beginRelationClaimModelRefresh,
  blurRelationClaimModel,
  finishRelationClaimModelRefresh,
  focusRelationClaimModel,
  RelationClaimUnavailable,
  relationClaimModelFlight,
  relationClaimModelSection,
  switchRelationClaimModel,
  type ConfirmedRelationClaims,
  type RelationClaimKind,
  type RelationClaimModel,
} from './relationClaimFlow';
import { createRelationClaimSession, relationClaimFlight, shouldResetRelationClaims } from './relationClaimSession';
import { userFacingVerificationMessage } from './verificationErrors';

const EMPTY_CONFIRMED: ConfirmedRelationClaims = {
  OWNERSHIP: false,
  MANAGEMENT: false,
};

const EMPTY_FLIGHT = {
  inFlight: false,
  notice: null as string | null,
  errorMessage: null as string | null,
};

function emptyModel(userKey: string | null): RelationClaimModel {
  return {
    session: createRelationClaimSession(userKey),
    held: null,
    visible: null,
    confirmed: EMPTY_CONFIRMED,
    pending: EMPTY_CONFIRMED,
  };
}

export function useRelationClaims(equineId: string) {
  const { session } = useAuth();
  const userKey = session?.user.id ?? null;
  const modelRef = useRef<RelationClaimModel>(emptyModel(userKey));
  const [snapshot, setSnapshot] = useState<RelationClaimSnapshot | null>(null);
  const [confirmed, setConfirmed] = useState<ConfirmedRelationClaims>(EMPTY_CONFIRMED);
  const [isLoading, setIsLoading] = useState(Boolean(userKey));
  const [flight, setFlight] = useState(EMPTY_FLIGHT);

  if (shouldResetRelationClaims(modelRef.current.session, userKey, equineId)) {
    modelRef.current = switchRelationClaimModel(modelRef.current, userKey, equineId);
    setSnapshot(null);
    setConfirmed(EMPTY_CONFIRMED);
    setFlight(EMPTY_FLIGHT);
    setIsLoading(Boolean(userKey));
  }

  const paint = useCallback((model: RelationClaimModel) => {
    modelRef.current = model;
    setSnapshot(model.visible);
    setConfirmed(model.confirmed);
    setFlight(relationClaimFlight(model.session));
  }, []);

  const refresh = useCallback(async () => {
    if (!userKey) {
      const cleared = {
        ...modelRef.current,
        held: null,
        visible: null,
        confirmed: EMPTY_CONFIRMED,
        pending: EMPTY_CONFIRMED,
      };
      paint(cleared);
      setIsLoading(false);
      return;
    }

    const started = beginRelationClaimModelRefresh(modelRef.current);
    if (!started) {
      paint({
        ...modelRef.current,
        held: null,
        visible: null,
        confirmed: EMPTY_CONFIRMED,
        pending: EMPTY_CONFIRMED,
      });
      setIsLoading(false);
      return;
    }

    modelRef.current = started.model;
    const refreshToken = started.refresh;
    setIsLoading(true);

    try {
      const next = await loadRelationClaimSnapshot();
      const finished = finishRelationClaimModelRefresh(modelRef.current, refreshToken, {
        ok: true,
        snapshot: next,
      });
      if (!finished.paint) return;
      modelRef.current = finished.model;
      if (!finished.model.session.inFlight) {
        setSnapshot(finished.model.visible);
        setConfirmed(finished.model.confirmed);
      }
      setFlight(relationClaimModelFlight(finished.model));
    } catch (error) {
      const finished = finishRelationClaimModelRefresh(modelRef.current, refreshToken, {
        ok: false,
        errorMessage: userFacingVerificationMessage(error),
      });
      if (!finished.paint) return;
      modelRef.current = finished.model;
      if (!finished.model.session.inFlight) {
        setSnapshot(finished.model.visible);
        setConfirmed(finished.model.confirmed);
      }
      setFlight(relationClaimModelFlight(finished.model));
    } finally {
      if (
        refreshToken.refreshSeq === modelRef.current.session.refreshSeq &&
        refreshToken.userKey === modelRef.current.session.userKey &&
        refreshToken.equineId === modelRef.current.session.equineId &&
        modelRef.current.session.screenActive
      ) {
        setIsLoading(false);
      }
    }
  }, [equineId, paint, userKey]);

  const submit = useCallback(
    async (kind: RelationClaimKind) => {
      if (!userKey) return;

      await attemptRelationClaimSubmit({
        model: modelRef.current,
        kind,
        userKey,
        equineId,
        notice: CLAIM_RECORDED_NOTICE,
        readModel: () => modelRef.current,
        writeModel: (next) => {
          modelRef.current = next;
          if (next.session.screenActive) paint(next);
        },
        mutate: async () => {
          const current = relationClaimModelSection(modelRef.current, equineId);
          const ownershipPayload = current?.ownership.ownershipPayload ?? null;
          const managementPayload = current?.management.managementPayload ?? null;
          if (kind === 'OWNERSHIP') {
            if (!ownershipPayload) throw new RelationClaimUnavailable();
            await submitOwnershipClaim(ownershipPayload);
            return;
          }
          if (!managementPayload) throw new RelationClaimUnavailable();
          await submitManagementClaim(managementPayload);
        },
        loadSnapshot: () => loadRelationClaimSnapshot(),
      });
    },
    [equineId, paint, userKey],
  );

  useFocusEffect(
    useCallback(() => {
      const focused = focusRelationClaimModel(modelRef.current);
      paint(focused);
      void refresh();
      return () => {
        modelRef.current = blurRelationClaimModel(modelRef.current);
      };
    }, [paint, refresh]),
  );

  const section: RelationClaimSection | null = snapshot
    ? relationClaimModelSection(
        {
          session: modelRef.current.session,
          held: snapshot,
          visible: snapshot,
          confirmed,
          pending: modelRef.current.pending,
        },
        equineId,
      )
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
