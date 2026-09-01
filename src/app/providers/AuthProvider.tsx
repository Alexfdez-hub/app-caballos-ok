import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Platform } from 'react-native';
import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import type { Session } from '@supabase/supabase-js';

import { AuthContext } from '../../features/auth/AuthContext';
import { createSessionFromUrl } from '../../features/auth/authLinks';
import {
  logAuthFailure,
  userFacingAuthMessage,
} from '../../features/auth/authErrors';
import { supabase } from '../../services/supabase/client';

type AuthProviderProps = {
  children: ReactNode;
};

if (Platform.OS === 'web') {
  WebBrowser.maybeCompleteAuthSession();
}

function getWebLocationHref() {
  if (Platform.OS !== 'web' || typeof window === 'undefined') {
    return null;
  }

  return window.location.href;
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [session, setSession] = useState<Session | null>(null);
  const [isRestoringSession, setIsRestoringSession] = useState(true);
  const [isPasswordRecovery, setIsPasswordRecovery] = useState(false);
  const [authLinkError, setAuthLinkError] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;

    async function handleAuthUrl(url: string | null) {
      if (!url || !isMounted) {
        return;
      }

      const result = await createSessionFromUrl(url);

      if (result.ignored) {
        return;
      }

      if (result.error) {
        logAuthFailure('callback', result.error);
        if (isMounted) {
          setAuthLinkError(userFacingAuthMessage('callback', result.error));
        }
        return;
      }

      if (isMounted) {
        setAuthLinkError(null);
        if (result.type === 'recovery') {
          setIsPasswordRecovery(true);
        }
      }
    }

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, nextSession) => {
      if (!isMounted) {
        return;
      }

      setSession(nextSession);
      setIsRestoringSession(false);

      if (event === 'PASSWORD_RECOVERY') {
        setIsPasswordRecovery(true);
        setAuthLinkError(null);
      }

      if (event === 'SIGNED_OUT') {
        setIsPasswordRecovery(false);
      }
    });

    void supabase.auth.getSession().then(({ data }) => {
      if (isMounted) {
        setSession(data.session);
        setIsRestoringSession(false);
      }
    });

    void Linking.getInitialURL().then((url) => {
      void handleAuthUrl(url ?? getWebLocationHref());
    });

    const linking = Linking.addEventListener('url', (event) => {
      void handleAuthUrl(event.url);
    });

    return () => {
      isMounted = false;
      subscription.unsubscribe();
      linking.remove();
    };
  }, []);

  const value = useMemo(
    () => ({
      session,
      isRestoringSession,
      isPasswordRecovery,
      authLinkError,
      completePasswordRecovery: () => setIsPasswordRecovery(false),
      clearAuthLinkError: () => setAuthLinkError(null),
    }),
    [authLinkError, isPasswordRecovery, isRestoringSession, session],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
