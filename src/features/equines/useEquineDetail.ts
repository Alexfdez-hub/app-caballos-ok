import { useCallback, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { userFacingEquineCreateMessage } from './equineCreate';
import { getMyEquine } from './equineCreateService';
import type { MyEquineDetail } from './equineCreate';

export function useEquineDetail(equineId: string) {
  const [equine, setEquine] = useState<MyEquineDetail | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage(null);
    try {
      setEquine(await getMyEquine(equineId));
    } catch (error) {
      setEquine(null);
      setErrorMessage(userFacingEquineCreateMessage(error));
    } finally {
      setIsLoading(false);
    }
  }, [equineId]);

  useFocusEffect(
    useCallback(() => {
      void refresh();
    }, [refresh]),
  );

  return { equine, isLoading, errorMessage, refresh };
}
