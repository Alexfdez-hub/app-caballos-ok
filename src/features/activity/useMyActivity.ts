import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { shouldApplyCenterMembershipRefresh } from '../centers/membershipRefresh';
import { userFacingActivityMessage } from './activityErrors';
import { listMyActivity } from './activityService';
import type { ActivityBooking } from './types';

export function useMyActivity() {
  const [rows, setRows] = useState<ActivityBooking[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const requestSeqRef = useRef(0);
  const isScreenActiveRef = useRef(false);

  const refresh = useCallback(async () => {
    const requestSeq = requestSeqRef.current + 1;
    requestSeqRef.current = requestSeq;
    setIsLoading(true);
    setErrorMessage(null);

    try {
      const nextRows = await listMyActivity();
      if (
        !shouldApplyCenterMembershipRefresh(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
        )
      ) {
        return;
      }
      setRows(nextRows);
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
      setRows([]);
      setErrorMessage(userFacingActivityMessage(error));
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
  }, []);

  useFocusEffect(
    useCallback(() => {
      isScreenActiveRef.current = true;
      void refresh();
      return () => {
        isScreenActiveRef.current = false;
      };
    }, [refresh]),
  );

  return { rows, isLoading, errorMessage, refresh };
}
