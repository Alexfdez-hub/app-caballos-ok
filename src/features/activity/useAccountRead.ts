import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import {
  beginAccountRead,
  idleAccountRead,
  retargetAccountRead,
  settleAccountRead,
  type AccountRead,
} from './accountSnapshot';

export function useAccountRead<T>(
  userId: string | null,
  load: () => Promise<T[]>,
  mapError: (error: unknown) => string,
): { read: AccountRead<T>; refresh: () => Promise<void> } {
  const [read, setRead] = useState<AccountRead<T>>(() => idleAccountRead(userId));
  const requestSeqRef = useRef(read.requestSeq);
  const isScreenActiveRef = useRef(false);
  const userIdRef = useRef(userId);
  userIdRef.current = userId;

  if (read.ownerUserId !== userId) {
    const next = retargetAccountRead(read, userId);
    requestSeqRef.current = next.requestSeq;
    setRead(next);
  }

  const refresh = useCallback(async () => {
    const requestedUserId = userIdRef.current;
    const requestSeq = requestSeqRef.current + 1;
    requestSeqRef.current = requestSeq;
    setRead((current) => beginAccountRead(current, requestedUserId, requestSeq));

    if (requestedUserId === null) {
      return;
    }

    try {
      const rows = await load();
      setRead((current) =>
        settleAccountRead(current, {
          requestSeq,
          requestedUserId,
          currentUserId: userIdRef.current,
          screenActive: isScreenActiveRef.current,
          ok: true,
          rows,
          errorMessage: null,
        }),
      );
    } catch (error) {
      setRead((current) =>
        settleAccountRead(current, {
          requestSeq,
          requestedUserId,
          currentUserId: userIdRef.current,
          screenActive: isScreenActiveRef.current,
          ok: false,
          rows: [],
          errorMessage: mapError(error),
        }),
      );
    }
  }, [load, mapError]);

  useFocusEffect(
    useCallback(() => {
      isScreenActiveRef.current = true;
      void refresh();
      return () => {
        isScreenActiveRef.current = false;
      };
    }, [refresh, userId]),
  );

  return { read, refresh };
}
