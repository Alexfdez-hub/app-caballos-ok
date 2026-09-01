import { useCallback, useEffect, useState } from 'react';

import { userFacingGuardianMessage } from './guardianErrors';
import {
  grantGuardianConsent,
  listMyGuardianConsents,
  listMyGuardianRelationships,
  revokeGuardianConsent,
} from './guardianService';
import type { GuardianConsent, GuardianRelationship } from './types';

export function useGuardians() {
  const [relationships, setRelationships] = useState<GuardianRelationship[]>(
    [],
  );
  const [consents, setConsents] = useState<GuardianConsent[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isMutating, setIsMutating] = useState(false);

  const refresh = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage(null);

    try {
      const [nextRelationships, nextConsents] = await Promise.all([
        listMyGuardianRelationships(),
        listMyGuardianConsents(),
      ]);
      setRelationships(nextRelationships);
      setConsents(nextConsents);
    } catch (error) {
      setErrorMessage(userFacingGuardianMessage(error));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const grant = useCallback(
    async (relationshipId: string, marketCode: string) => {
      setIsMutating(true);
      setErrorMessage(null);

      try {
        await grantGuardianConsent({ relationshipId, marketCode });
        await refresh();
      } catch (error) {
        setErrorMessage(userFacingGuardianMessage(error));
      } finally {
        setIsMutating(false);
      }
    },
    [refresh],
  );

  const revoke = useCallback(
    async (consentId: string) => {
      setIsMutating(true);
      setErrorMessage(null);

      try {
        await revokeGuardianConsent(consentId);
        await refresh();
      } catch (error) {
        setErrorMessage(userFacingGuardianMessage(error));
      } finally {
        setIsMutating(false);
      }
    },
    [refresh],
  );

  return {
    relationships,
    consents,
    isLoading,
    isMutating,
    errorMessage,
    refresh,
    grant,
    revoke,
  };
}
