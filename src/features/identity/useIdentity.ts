import { useContext } from 'react';

import { IdentityContext } from './IdentityContext';

export function useIdentity() {
  const identity = useContext(IdentityContext);

  if (!identity) {
    throw new Error('useIdentity must be used within IdentityProvider.');
  }

  return identity;
}
