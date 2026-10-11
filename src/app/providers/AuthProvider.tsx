import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Platform } from 'react-native';
import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import type { Session } from '@supabase/supabase-js';

import { AuthContext } from '../../features/auth/AuthContext';
import {
  claimAuthCallback,
  establishSessionFromCallback,
  interpretAuthCallbackUrl,
  reduceAuthCallbackResult,
} from '../../features/auth/authCallback';
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
  const [isProcessingAuthLink, setIsProcessingAuthLink] = useState(false);
  const [authLinkError, setAuthLinkError] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;
    let acceptedCallback = false;

    async function handleAuthUrl(url: string | null) {
      if (!url || !isMounted) {
        return;
      }

      if (claimAuthCallback(url) !== 'claimed') {
        return;
      }

      setIsProcessingAuthLink(true);
      setAuthLinkError(null);

      try {
        const result = await establishSessionFromCallback(
          interpretAuthCallbackUrl(url),
          {
            exchangeCodeForSession: (code) =>
              supabase.auth.exchangeCodeForSession(code),
            setSession: (tokens) => supabase.auth.setSession(tokens),
            verifyOtp: (params) => supabase.auth.verifyOtp(params),
          },
        );

        if (!isMounted || result.ignored) {
          return;
        }

        const next = reduceAuthCallbackResult(
          { acceptedCallback, isPasswordRecovery: false },
          result,
        );
        acceptedCallback = next.acceptedCallback;

        if (result.error) {
          if (next.showError) {
            logAuthFailure('callback', result.error);
            setAuthLinkError(userFacingAuthMessage('callback', result.error));
          }
          return;
        }

        setAuthLinkError(null);
        setIsPasswordRecovery(next.isPasswordRecovery);
      } catch (error) {
        if (isMounted && !acceptedCallback) {
          logAuthFailure('callback', error);
          setAuthLinkError(userFacingAuthMessage('callback', error));
        }
      } finally {
        if (isMounted) {
          setIsProcessingAuthLink(false);
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
      isProcessingAuthLink,
      authLinkError,
      completePasswordRecovery: () => setIsPasswordRecovery(false),
      clearAuthLinkError: () => setAuthLinkError(null),
    }),
    [
      authLinkError,
      isPasswordRecovery,
      isProcessingAuthLink,
      isRestoringSession,
      session,
    ],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
