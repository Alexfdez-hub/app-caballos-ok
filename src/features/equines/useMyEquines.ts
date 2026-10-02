import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { shouldApplyCenterMembershipRefresh } from '../centers/membershipRefresh';
import { userFacingEquineCreateMessage } from './equineCreate';
import { listMyEquines } from './equineCreateService';
import type { MyEquineSummary } from './equineCreate';

export function useMyEquines() {
  const [rows, setRows] = useState<MyEquineSummary[]>([]);
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
      const nextRows = await listMyEquines();
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
      setErrorMessage(userFacingEquineCreateMessage(error));
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
