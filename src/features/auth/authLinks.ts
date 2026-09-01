import { Platform } from 'react-native';
import { makeRedirectUri } from 'expo-auth-session';

import { supabase } from '../../services/supabase/client';
import {
  AUTH_APP_SCHEME,
  AUTH_NATIVE_REDIRECT_URI,
  AUTH_REDIRECT_PATH,
  interpretAuthCallbackUrl,
} from './authCallback';

export {
  AUTH_APP_SCHEME,
  AUTH_NATIVE_REDIRECT_URI,
  AUTH_NATIVE_REDIRECT_URI_TRIPLE,
  AUTH_REDIRECT_PATH,
  getAuthRedirectAllowList,
} from './authCallback';

export function getAuthRedirectUrl() {
  if (Platform.OS === 'web') {
    return makeRedirectUri({
      scheme: AUTH_APP_SCHEME,
      path: AUTH_REDIRECT_PATH,
    });
  }

  return AUTH_NATIVE_REDIRECT_URI;
}

export async function createSessionFromUrl(url: string) {
  const interpreted = interpretAuthCallbackUrl(url);

  if (interpreted.status === 'ignored') {
    return { type: null, error: null, ignored: true as const };
  }

  if (interpreted.status === 'error') {
    return { type: interpreted.type, error: interpreted.error };
  }

  if (interpreted.status === 'code') {
    const { error } = await supabase.auth.exchangeCodeForSession(
      interpreted.code,
    );
    return { type: interpreted.type, error };
  }

  const { error } = await supabase.auth.setSession({
    access_token: interpreted.accessToken,
    refresh_token: interpreted.refreshToken,
  });

  return { type: interpreted.type, error };
}
