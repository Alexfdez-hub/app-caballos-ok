import { useCallback } from 'react';

import { useAccountRead } from '../activity/useAccountRead';
import { userFacingExploreMessage } from './exploreErrors';
import { listBookingsICanConfirm } from './exploreService';
import type { ConfirmableBooking } from './types';

export function useConfirmQueue(userId: string | null) {
  const load = useCallback(() => listBookingsICanConfirm(), []);
  const mapError = useCallback(
    (error: unknown) => userFacingExploreMessage(error),
    [],
  );
  return useAccountRead<ConfirmableBooking>(userId, load, mapError);
}
