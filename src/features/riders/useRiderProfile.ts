import { useCallback, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { userFacingRiderMessage } from './riderErrors';
import { getMyRiderProfile, upsertMyRiderProfile } from './riderService';
import type { RiderProfile, UpsertRiderProfileInput } from './types';

export function useRiderProfile() {
  const [profile, setProfile] = useState<RiderProfile | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage(null);

    try {
      setProfile(await getMyRiderProfile());
    } catch (error) {
      setErrorMessage(userFacingRiderMessage(error));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      void refresh();
    }, [refresh]),
  );

  const saveProfile = useCallback(async (input: UpsertRiderProfileInput) => {
    setIsSaving(true);
    setErrorMessage(null);

    try {
      const nextProfile = await upsertMyRiderProfile(input);
      setProfile(nextProfile);
      return nextProfile;
    } catch (error) {
      setErrorMessage(userFacingRiderMessage(error));
      throw error;
    } finally {
      setIsSaving(false);
    }
  }, []);

  return {
    profile,
    isLoading,
    isSaving,
    errorMessage,
    refresh,
    saveProfile,
  };
}
