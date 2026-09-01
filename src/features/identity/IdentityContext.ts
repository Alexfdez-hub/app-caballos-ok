import { createContext } from 'react';

import type { CompleteIdentityInput, Identity } from './types';

export type IdentityContextValue = {
  identity: Identity | null;
  isLoadingIdentity: boolean;
  identityError: boolean;
  completeIdentity: (input: CompleteIdentityInput) => Promise<void>;
  refreshIdentity: () => Promise<void>;
};

export const IdentityContext = createContext<
  IdentityContextValue | undefined
>(undefined);
