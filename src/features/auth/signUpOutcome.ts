import type { AuthError, Session, User } from '@supabase/supabase-js';

export type SignUpOutcome =
  | 'authenticated'
  | 'pending_confirmation'
  | 'existing_email';

export function classifySignUpResult(
  data: { user: User | null; session: Session | null } | null,
  error: AuthError | null,
): SignUpOutcome | null {
  if (error || !data) {
    return null;
  }

  if (data.session) {
    return 'authenticated';
  }

  if (Array.isArray(data.user?.identities) && data.user.identities.length === 0) {
    return 'existing_email';
  }

  return 'pending_confirmation';
}
