import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { shouldApplyAccountResult } from './accountResult';
import { userFacingExploreMessage } from './exploreErrors';
import { listBookableOffers } from './exploreService';
import type { ExploreRange } from './exploreRange';
import type { BookableOffer } from './types';

export function useBookableOffers(userId: string | null, range: ExploreRange) {
  const [rows, setRows] = useState<BookableOffer[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const requestSeqRef = useRef(0);
  const isScreenActiveRef = useRef(false);
  const userIdRef = useRef(userId);
  const rangeRef = useRef(range);
  userIdRef.current = userId;
  rangeRef.current = range;

  const refresh = useCallback(async () => {
    const requestSeq = requestSeqRef.current + 1;
    requestSeqRef.current = requestSeq;
    const requestedUserId = userIdRef.current;
    const requestedRange = rangeRef.current;
    setIsLoading(true);
    setErrorMessage(null);

    try {
      const nextRows = await listBookableOffers(requestedRange.start, requestedRange.end);
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
    }, [refresh, range.start, range.end, userId]),
  );

  return { rows, isLoading, errorMessage, refresh };
}
