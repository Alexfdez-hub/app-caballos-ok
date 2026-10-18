import { useCallback } from 'react';

import { userFacingActivityMessage } from './activityErrors';
import { listMyActivity } from './activityService';
import { useAccountRead } from './useAccountRead';
import type { ActivityBooking } from './types';

export function useMyActivity(userId: string | null) {
  const load = useCallback(() => listMyActivity(), []);
  const mapError = useCallback(
    (error: unknown) => userFacingActivityMessage(error),
    [],
  );
  return useAccountRead<ActivityBooking>(userId, load, mapError);
}
