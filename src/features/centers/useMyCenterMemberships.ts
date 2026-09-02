import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { userFacingCenterMembershipMessage } from './centerMembershipErrors';
import { listMyCenterMemberships } from './centerMembershipService';
import { groupMembershipsByCenter } from './labels';
import { shouldApplyCenterMembershipRefresh } from './membershipRefresh';
import type { CenterMembershipGroup } from './types';

export function useMyCenterMemberships() {
  const [groups, setGroups] = useState<CenterMembershipGroup[]>([]);
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
      const memberships = await listMyCenterMemberships();
      if (
        !shouldApplyCenterMembershipRefresh(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
        )
      ) {
        return;
      }
      setGroups(groupMembershipsByCenter(memberships));
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
      setErrorMessage(userFacingCenterMembershipMessage(error));
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

  return {
    groups,
    isLoading,
    errorMessage,
    refresh,
  };
}
