import { createContext } from 'react';
import type { Session } from '@supabase/supabase-js';

export type AuthContextValue = {
  session: Session | null;
  isRestoringSession: boolean;
};

export const AuthContext = createContext<AuthContextValue | undefined>(undefined);
