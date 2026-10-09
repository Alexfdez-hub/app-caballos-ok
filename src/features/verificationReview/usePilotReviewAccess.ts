import { useCallback, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import { useAuth } from '../auth/useAuth';
import { pilotReviewIsVisible } from './presentation';
import { loadReviewCapabilities } from './reviewService';
import {
  beginReviewLoad,
  createReviewPilotSession,
  markReviewBlurred,
  markReviewFocused,
  reviewUserKey,
  shouldApplyReviewResult,
  shouldResetReview,
  switchReviewUser,
} from './reviewSession';

export function usePilotReviewAccess(): boolean {
  const { session } = useAuth();
  const userKey = reviewUserKey(session?.user.id);
  const gateRef = useRef(createReviewPilotSession(userKey));
  const [visible, setVisible] = useState(false);

  if (shouldResetReview(gateRef.current.userKey, userKey)) {
    gateRef.current = switchReviewUser(gateRef.current, userKey);
    if (visible) {
      setVisible(false);
    }
  }

  useFocusEffect(
    useCallback(() => {
      if (!userKey) {
        gateRef.current = switchReviewUser(gateRef.current, null);
        setVisible(false);
        return undefined;
      }

      gateRef.current = markReviewFocused(gateRef.current);
      const started = beginReviewLoad(gateRef.current, userKey);
      gateRef.current = started.session;
      const request = started.request;

      void loadReviewCapabilities()
        .then((capabilities) => {
          if (!shouldApplyReviewResult(request, gateRef.current)) {
            return;
          }

          setVisible(pilotReviewIsVisible(capabilities));
        })
        .catch(() => {
          if (!shouldApplyReviewResult(request, gateRef.current)) {
            return;
          }

          setVisible(false);
        });

      return () => {
        gateRef.current = markReviewBlurred(gateRef.current);
      };
    }, [userKey]),
  );

  return visible;
}
