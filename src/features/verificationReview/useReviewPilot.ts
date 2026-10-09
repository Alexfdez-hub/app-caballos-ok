import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { useAuth } from '../auth/useAuth';
import { presentReviewScreen } from './presentation';
import { isReviewDenied, userFacingReviewMessage } from './reviewErrors';
import {
  loadReviewCapabilities,
  loadReviewCase,
  loadReviewQueue,
} from './reviewService';
import {
  beginReviewLoad,
  createReviewPilotSession,
  markReviewBlurred,
  markReviewFocused,
  reviewUserKey,
  shouldApplyReviewResult,
  shouldResetReview,
} from './reviewSession';
import type { ReviewDetailView, ReviewQueueItem, ReviewScreenView } from './types';

const EMPTY_DETAIL: ReviewDetailView = { kind: 'none' };

export function useReviewPilot(): ReviewScreenView & {
  refresh: () => void;
  openCase: (caseType: string, caseId: string) => void;
  actionsBlocked: boolean;
} {
  const { session } = useAuth();
  const userKey = reviewUserKey(session?.user.id);
  const sessionRef = useRef(createReviewPilotSession(userKey));
  const [isLoading, setIsLoading] = useState(false);
  const [hadAccess, setHadAccess] = useState(false);
  const [denied, setDenied] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [items, setItems] = useState<ReviewQueueItem[]>([]);
  const [detail, setDetail] = useState<ReviewDetailView>(EMPTY_DETAIL);

  const clearPrivateData = useCallback(() => {
    setHadAccess(false);
    setDenied(false);
    setErrorMessage(null);
    setItems([]);
    setDetail(EMPTY_DETAIL);
    setIsLoading(false);
  }, []);

  if (shouldResetReview(sessionRef.current.userKey, userKey)) {
    sessionRef.current = createReviewPilotSession(userKey);
    clearPrivateData();
  }

  const refresh = useCallback(() => {
    if (!userKey) {
      clearPrivateData();
      return;
    }

    const started = beginReviewLoad(sessionRef.current, userKey);
    sessionRef.current = started.session;
    const requestSeq = started.requestSeq;
    setIsLoading(true);
    setErrorMessage(null);
    setDenied(false);

    void (async () => {
      try {
        const capabilities = await loadReviewCapabilities();

        if (
          !shouldApplyReviewResult(
            requestSeq,
            sessionRef.current.requestSeq,
            sessionRef.current.screenActive,
          )
        ) {
          return;
        }

        if (capabilities.length === 0) {
          setDenied(true);
          setItems([]);
          setDetail(EMPTY_DETAIL);
          return;
        }

        const queue = await loadReviewQueue();

        if (
          !shouldApplyReviewResult(
            requestSeq,
            sessionRef.current.requestSeq,
            sessionRef.current.screenActive,
          )
        ) {
          return;
        }

        setHadAccess(true);
        setDenied(false);
        setItems(queue);
        setDetail(EMPTY_DETAIL);
      } catch (error) {
        if (
          !shouldApplyReviewResult(
            requestSeq,
            sessionRef.current.requestSeq,
            sessionRef.current.screenActive,
          )
        ) {
          return;
        }

        setItems([]);
        setDetail(EMPTY_DETAIL);

        if (isReviewDenied(error)) {
          setDenied(true);
          return;
        }

        setErrorMessage(userFacingReviewMessage(error));
      } finally {
        if (
          shouldApplyReviewResult(
            requestSeq,
            sessionRef.current.requestSeq,
            sessionRef.current.screenActive,
          )
        ) {
          sessionRef.current = { ...sessionRef.current, loading: false };
          setIsLoading(false);
        }
      }
    })();
  }, [clearPrivateData, userKey]);

  const openCase = useCallback(
    (caseType: string, caseId: string) => {
      if (!userKey) {
        clearPrivateData();
        return;
      }

      const started = beginReviewLoad(sessionRef.current, userKey);
      sessionRef.current = started.session;
      const requestSeq = started.requestSeq;
      setIsLoading(true);

      void (async () => {
        try {
          const opened = await loadReviewCase(caseType, caseId);

          if (
            !shouldApplyReviewResult(
              requestSeq,
              sessionRef.current.requestSeq,
              sessionRef.current.screenActive,
            )
          ) {
            return;
          }

          setDetail({ kind: 'ready', detail: opened });
          setDenied(false);
        } catch (error) {
          if (
            !shouldApplyReviewResult(
              requestSeq,
              sessionRef.current.requestSeq,
              sessionRef.current.screenActive,
            )
          ) {
            return;
          }

          setDetail({ kind: 'unavailable' });

          if (!isReviewDenied(error)) {
            setErrorMessage(userFacingReviewMessage(error));
            return;
          }

          try {
            const capabilities = await loadReviewCapabilities();

            if (
              !shouldApplyReviewResult(
                requestSeq,
                sessionRef.current.requestSeq,
                sessionRef.current.screenActive,
              )
            ) {
              return;
            }

            if (capabilities.length === 0) {
              setDenied(true);
              setItems([]);
              setDetail(EMPTY_DETAIL);
            }
          } catch (capabilityError) {
            if (
              !shouldApplyReviewResult(
                requestSeq,
                sessionRef.current.requestSeq,
                sessionRef.current.screenActive,
              )
            ) {
              return;
            }

            if (isReviewDenied(capabilityError)) {
              setDenied(true);
              setItems([]);
              setDetail(EMPTY_DETAIL);
            }
          }
        } finally {
          if (
            shouldApplyReviewResult(
              requestSeq,
              sessionRef.current.requestSeq,
              sessionRef.current.screenActive,
            )
          ) {
            sessionRef.current = { ...sessionRef.current, loading: false };
            setIsLoading(false);
          }
        }
      })();
    },
    [clearPrivateData, userKey],
  );

  useFocusEffect(
    useCallback(() => {
      sessionRef.current = markReviewFocused(sessionRef.current);
      refresh();

      return () => {
        sessionRef.current = markReviewBlurred(sessionRef.current);
        setIsLoading(false);
      };
    }, [refresh]),
  );

  const view = presentReviewScreen({
    hasSession: userKey !== null,
    isLoading,
    hadAccess,
    denied,
    errorMessage,
    items,
    detail,
  });

  return {
    ...view,
    refresh,
    openCase,
    actionsBlocked: isLoading && sessionRef.current.screenActive,
  };
}
