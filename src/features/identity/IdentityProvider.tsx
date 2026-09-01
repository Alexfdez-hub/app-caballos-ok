import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';

import { useAuth } from '../auth/useAuth';
import { IdentityContext } from './IdentityContext';
import { completeMyIdentity, ensureMyIdentity } from './identityService';
import type { CompleteIdentityInput, Identity } from './types';

type IdentityProviderProps = {
  children: ReactNode;
};

export function IdentityProvider({ children }: IdentityProviderProps) {
  const { session } = useAuth();
  const authUserId = session?.user.id ?? null;
  const [identity, setIdentity] = useState<Identity | null>(null);
  const [loadedAuthUserId, setLoadedAuthUserId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [identityError, setIdentityError] = useState(false);

  useEffect(() => {
    let isActive = true;

    if (!authUserId) {
      setIdentity(null);
      setLoadedAuthUserId(null);
      setIsLoading(false);
      setIdentityError(false);
      return () => {
        isActive = false;
      };
    }

    setIdentity(null);
    setLoadedAuthUserId(null);
    setIdentityError(false);
    setIsLoading(true);

    void ensureMyIdentity()
      .then((nextIdentity) => {
        if (isActive) {
          setIdentity(nextIdentity);
          setLoadedAuthUserId(authUserId);
        }
      })
      .catch(() => {
        if (isActive) {
          setIdentityError(true);
          setLoadedAuthUserId(authUserId);
        }
      })
      .finally(() => {
        if (isActive) {
          setIsLoading(false);
        }
      });

    return () => {
      isActive = false;
    };
  }, [authUserId]);

  const refreshIdentity = useCallback(async () => {
    if (!authUserId) {
      return;
    }

    setIsLoading(true);
    setIdentityError(false);

    try {
      const nextIdentity = await ensureMyIdentity();
      setIdentity(nextIdentity);
      setLoadedAuthUserId(authUserId);
    } catch {
      setIdentityError(true);
      setLoadedAuthUserId(authUserId);
    } finally {
      setIsLoading(false);
    }
  }, [authUserId]);

  const completeIdentity = useCallback(
    async (input: CompleteIdentityInput) => {
      if (!authUserId) {
        throw new Error('Authentication required.');
      }

      const nextIdentity = await completeMyIdentity(input);
      setIdentity(nextIdentity);
      setLoadedAuthUserId(authUserId);
      setIdentityError(false);
    },
    [authUserId],
  );

  const currentIdentity =
    authUserId && loadedAuthUserId === authUserId ? identity : null;
  const isLoadingIdentity =
    Boolean(authUserId) &&
    (isLoading || loadedAuthUserId !== authUserId);

  const value = useMemo(
    () => ({
      identity: currentIdentity,
      isLoadingIdentity,
      identityError,
      completeIdentity,
      refreshIdentity,
    }),
    [
      completeIdentity,
      currentIdentity,
      identityError,
      isLoadingIdentity,
      refreshIdentity,
    ],
  );

  return (
    <IdentityContext.Provider value={value}>
      {children}
    </IdentityContext.Provider>
  );
}
