import { useCallback, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { userFacingCenterMembershipMessage } from './centerMembershipErrors';
import { listMyCenterMemberships } from './centerMembershipService';
import { groupMembershipsByCenter } from './labels';
import type { CenterMembershipGroup } from './types';

export function useMyCenterMemberships() {
  const [groups, setGroups] = useState<CenterMembershipGroup[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage(null);

    try {
      const memberships = await listMyCenterMemberships();
      setGroups(groupMembershipsByCenter(memberships));
    } catch (error) {
      setErrorMessage(userFacingCenterMembershipMessage(error));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      void refresh();
    }, [refresh]),
  );

  return {
    groups,
    isLoading,
    errorMessage,
    refresh,
  };
}
