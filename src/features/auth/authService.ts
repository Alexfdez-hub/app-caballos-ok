import { supabase } from '../../services/supabase/client';
import { getAuthRedirectUrl } from './authLinks';

export { classifySignUpResult } from './signUpOutcome';
export type { SignUpOutcome } from './signUpOutcome';

export async function signInWithEmail(email: string, password: string) {
  return supabase.auth.signInWithPassword({
    email: email.trim(),
    password,
  });
}

export async function signUpWithEmail(email: string, password: string) {
  return supabase.auth.signUp({
    email: email.trim(),
    password,
    options: {
      emailRedirectTo: getAuthRedirectUrl(),
    },
  });
}

export async function resendSignupConfirmation(email: string) {
  return supabase.auth.resend({
    type: 'signup',
    email: email.trim(),
    options: {
      emailRedirectTo: getAuthRedirectUrl(),
    },
  });
}

export async function requestPasswordReset(email: string) {
  return supabase.auth.resetPasswordForEmail(email.trim(), {
    redirectTo: getAuthRedirectUrl(),
  });
}

export async function updatePassword(password: string) {
  return supabase.auth.updateUser({ password });
}

export async function signOut() {
  return supabase.auth.signOut();
}
