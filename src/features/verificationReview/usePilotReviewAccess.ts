import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { useAuth } from '../auth/useAuth';
import { pilotReviewIsVisible } from './presentation';
import { loadReviewCapabilities } from './reviewService';
import {
  reviewUserKey,
  shouldResetReview,
} from './reviewSession';

export function usePilotReviewAccess(): boolean {
  const { session } = useAuth();
  const userKey = reviewUserKey(session?.user.id);
  const keyRef = useRef(userKey);
  const [visible, setVisible] = useState(false);

  if (shouldResetReview(keyRef.current, userKey)) {
    keyRef.current = userKey;
    if (visible) {
      setVisible(false);
    }
  }

  useFocusEffect(
    useCallback(() => {
      let active = true;

      if (!userKey) {
        setVisible(false);
        return undefined;
      }

      void loadReviewCapabilities()
        .then((capabilities) => {
          if (active) {
            setVisible(pilotReviewIsVisible(capabilities));
          }
        })
        .catch(() => {
          if (active) {
            setVisible(false);
          }
        });

      return () => {
        active = false;
      };
    }, [userKey]),
  );

  return visible;
}
