import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { shouldApplyAccountResult } from './accountResult';
import { userFacingExploreMessage } from './exploreErrors';
import { listBookingsICanConfirm } from './exploreService';
import type { ConfirmableBooking } from './types';

export function useConfirmQueue(userId: string | null) {
  const [rows, setRows] = useState<ConfirmableBooking[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const requestSeqRef = useRef(0);
  const isScreenActiveRef = useRef(false);
  const userIdRef = useRef(userId);
  userIdRef.current = userId;

  const refresh = useCallback(async () => {
    const requestSeq = requestSeqRef.current + 1;
    requestSeqRef.current = requestSeq;
    const requestedUserId = userIdRef.current;
    setIsLoading(true);
    setErrorMessage(null);

    try {
      const nextRows = await listBookingsICanConfirm();
      if (
        !shouldApplyAccountResult(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
          requestedUserId,
          userIdRef.current,
        )
      ) {
        return;
      }
      setRows(nextRows);
    } catch (error) {
      if (
        !shouldApplyAccountResult(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
          requestedUserId,
          userIdRef.current,
        )
      ) {
        return;
      }
      setRows([]);
      setErrorMessage(userFacingExploreMessage(error));
    } finally {
      if (
        shouldApplyAccountResult(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
          requestedUserId,
          userIdRef.current,
        )
      ) {
        setIsLoading(false);
      }
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      isScreenActiveRef.current = true;
      void refresh();
      return () => {
        isScreenActiveRef.current = false;
      };
    }, [refresh, userId]),
  );

  return { rows, isLoading, errorMessage, refresh };
}
