import { Platform } from 'react-native';
import Constants from 'expo-constants';
import { makeRedirectUri } from 'expo-auth-session';

import { supabase } from '../../services/supabase/client';
import {
  establishSessionFromCallback,
  interpretAuthCallbackUrl,
  selectAuthRedirectUrl,
} from './authCallback';

export {
  AUTH_APP_SCHEME,
  AUTH_NATIVE_REDIRECT_URI,
  AUTH_NATIVE_REDIRECT_URI_TRIPLE,
  AUTH_REDIRECT_PATH,
  getAuthRedirectAllowList,
} from './authCallback';

export function getAuthRedirectUrl() {
  return selectAuthRedirectUrl({
    platformOs: Platform.OS,
    executionEnvironment: Constants.executionEnvironment,
    makeRedirectUri,
  });
}

export async function createSessionFromUrl(url: string) {
  return establishSessionFromCallback(interpretAuthCallbackUrl(url), {
    exchangeCodeForSession: (code) => supabase.auth.exchangeCodeForSession(code),
    setSession: (tokens) => supabase.auth.setSession(tokens),
    verifyOtp: (params) => supabase.auth.verifyOtp(params),
  });
}
