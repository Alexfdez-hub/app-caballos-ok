import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

import type { BookableOfferScreenProps } from '../app/navigation/types';
import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import { bookingStatusLabel } from '../features/activity/labels';
import type { BookingStatus } from '../features/activity/types';
import { useAuth } from '../features/auth/useAuth';
import { shouldApplyAccountResult } from '../features/explore/accountResult';
import {
  acceptBookingResult,
  acceptReconcileResult,
  applyReconcileFailure,
  bookingAttemptKey,
  canSubmitBooking,
  classifyBookingTransport,
  launchBookingAttempt,
  readBookingAttempt,
  showsReconcileAction,
  writeBookingAttempt,
  type BookingAttempt,
} from '../features/explore/bookingMutation';
import { userFacingExploreMessage } from '../features/explore/exploreErrors';
import { getBookableOffer, getMyBookingRequest, requestBookableSlot } from '../features/explore/exploreService';
import { formatOfferRange } from '../features/explore/formatOfferRange';
import type { BookableOffer } from '../features/explore/types';

function newRequestId(): string {
  const bytes = new Uint8Array(16);
  if (globalThis.crypto?.getRandomValues) {
    globalThis.crypto.getRandomValues(bytes);
  } else {
    for (let index = 0; index < bytes.length; index += 1) {
      bytes[index] = Math.floor(Math.random() * 256);
    }
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (value) => value.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export default function BookableOfferScreen({ route }: BookableOfferScreenProps) {
  const { session } = useAuth();
  const { equineId, centerId, serviceId, startsAt, endsAt } = route.params;
  const attemptKey = bookingAttemptKey({
    userId: session?.user.id ?? null,
    equineId,
    centerId,
    serviceId,
    startsAt,
    endsAt,
  });
  const heldAttempt = readBookingAttempt(attemptKey);
  const [offer, setOffer] = useState<BookableOffer | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [attempt, setAttempt] = useState<BookingAttempt>(heldAttempt);
  const requestSeqRef = useRef(0);
  const isScreenActiveRef = useRef(false);
  const userIdRef = useRef(session?.user.id ?? null);
  const attemptKeyRef = useRef(attemptKey);
  userIdRef.current = session?.user.id ?? null;
  attemptKeyRef.current = attemptKey;

  const publishAttempt = (key: string, next: BookingAttempt) => {
    writeBookingAttempt(key, next);
    if (key !== attemptKeyRef.current) {
      return;
    }
    setAttempt(next);
  };

  useEffect(() => {
    setAttempt(readBookingAttempt(attemptKey));
    setErrorMessage(null);
  }, [attemptKey]);

  const load = useCallback(async () => {
    const requestSeq = requestSeqRef.current + 1;
    requestSeqRef.current = requestSeq;
    const requestedUserId = userIdRef.current;
    setIsLoading(true);
    setErrorMessage(null);
    try {
      const next = await getBookableOffer({
        equineId,
        centerId,
        serviceId,
        startsAt,
        endsAt,
      });
      if (
        !shouldApplyAccountResult(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
          requestedUserId,
          userIdRef.current,
        )
      ) {
        return;
      }
      setOffer(next);
    } catch (error) {
      if (
        !shouldApplyAccountResult(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
          requestedUserId,
          userIdRef.current,
        )
      ) {
        return;
      }
      setOffer(null);
      setErrorMessage(userFacingExploreMessage(error));
    } finally {
      if (
        shouldApplyAccountResult(
          requestSeq,
          requestSeqRef.current,
          isScreenActiveRef.current,
          requestedUserId,
          userIdRef.current,
        )
      ) {
        setIsLoading(false);
      }
    }
  }, [centerId, endsAt, equineId, serviceId, startsAt]);

  useFocusEffect(
    useCallback(() => {
      isScreenActiveRef.current = true;
      void load();
      return () => {
        isScreenActiveRef.current = false;
      };
    }, [load]),
  );

  const submit = () => {
    if (!offer) {
      return;
    }
    const capturedKey = attemptKeyRef.current;
    const launched = launchBookingAttempt(readBookingAttempt(capturedKey), newRequestId());
    if (!launched.launched || !launched.attempt.clientRequestId) {
      return;
    }
    publishAttempt(capturedKey, launched.attempt);
    const requestId = launched.attempt.clientRequestId;
    const requestedUserId = userIdRef.current;
    void requestBookableSlot({
      clientRequestId: requestId,
      equineId: offer.equineId,
      centerId: offer.centerId,
      serviceId: offer.serviceId,
      startsAt: offer.startsAt,
      endsAt: offer.endsAt,
    })
      .then((result) => {
        const current = readBookingAttempt(capturedKey);
        publishAttempt(
          capturedKey,
          acceptBookingResult(current, 'ok', result.bookingStatus),
        );
        if (capturedKey === attemptKeyRef.current && requestedUserId === userIdRef.current) {
          setErrorMessage(null);
        }
      })
      .catch((error: unknown) => {
        const outcome = classifyBookingTransport(error);
        const current = readBookingAttempt(capturedKey);
        publishAttempt(capturedKey, acceptBookingResult(current, outcome, null));
        if (capturedKey !== attemptKeyRef.current || requestedUserId !== userIdRef.current) {
          return;
        }
        setErrorMessage(outcome === 'rejected' ? userFacingExploreMessage(error) : null);
      });
  };

  const reconcile = () => {
    const capturedKey = attemptKeyRef.current;
    const current = readBookingAttempt(capturedKey);
    if (!current.clientRequestId || !showsReconcileAction(current.phase)) {
      return;
    }
    const requestId = current.clientRequestId;
    const requestedUserId = userIdRef.current;
    void getMyBookingRequest(requestId)
      .then((lookup) => {
        const latest = readBookingAttempt(capturedKey);
        const serverOutcome = lookup?.outcome ?? 'ABSENT';
        publishAttempt(
          capturedKey,
          acceptReconcileResult(latest, serverOutcome, lookup?.bookingStatus ?? null),
        );
        if (capturedKey === attemptKeyRef.current && requestedUserId === userIdRef.current) {
          setErrorMessage(null);
        }
      })
      .catch((error: unknown) => {
        const latest = readBookingAttempt(capturedKey);
        publishAttempt(capturedKey, {
          ...latest,
          phase: applyReconcileFailure(latest.phase, error),
        });
        if (capturedKey !== attemptKeyRef.current || requestedUserId !== userIdRef.current) {
          return;
        }
        setErrorMessage(userFacingExploreMessage(error));
      });
  };

  const statusLabel = isBookingStatus(attempt.resultStatus)
    ? bookingStatusLabel(attempt.resultStatus)
    : attempt.resultStatus;

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Franja"
        subtitle="La solicitud no confirma la reserva y no inicia un pago."
      />
      {isLoading ? <ActivityIndicator color={colors.text} /> : null}
      {errorMessage ? (
        <Text accessibilityRole="alert" style={styles.message}>
          {errorMessage}
        </Text>
      ) : null}
      {!isLoading && !offer ? (
        <EmptyStateCard
          title="Franja no disponible"
          description="El servidor no devolvió esta franja para tu cuenta. Puede haber cambiado o quedar fuera de tu alcance."
        />
      ) : null}
      {offer ? (
        <SectionCard title={offer.centerName}>
          <Text style={styles.equine}>{offer.equineName}</Text>
          <Text style={styles.body}>{offer.serviceName}</Text>
          <Text style={styles.body}>
            {formatOfferRange(offer.startsAt, offer.endsAt, offer.centerTimezone)}
          </Text>
          <Text style={styles.note}>
            {offer.durationLimitMinutes === null
              ? 'No hay un máximo de duración aprobado. No se aplica uno por defecto.'
              : `Límite registrado: ${offer.durationLimitMinutes} min.`}
          </Text>
          {attempt.phase === 'succeeded' && statusLabel ? (
            <Text style={styles.body}>Solicitud registrada: {statusLabel}</Text>
          ) : null}
          {showsReconcileAction(attempt.phase) ? (
            <Text style={styles.message}>
              El resultado no llegó. No vuelvas a enviar la solicitud hasta reconciliarla.
            </Text>
          ) : null}
          {showsReconcileAction(attempt.phase) ? (
            <Pressable accessibilityRole="button" onPress={reconcile} style={styles.primaryButton}>
              <Text style={styles.primaryButtonText}>Reconciliar con el servidor</Text>
            </Pressable>
          ) : null}
          {canSubmitBooking(attempt.phase) ? (
            <Pressable accessibilityRole="button" onPress={submit} style={styles.primaryButton}>
              <Text style={styles.primaryButtonText}>Solicitar reserva</Text>
            </Pressable>
          ) : null}
          {attempt.phase === 'pending' ? <ActivityIndicator color={colors.text} /> : null}
        </SectionCard>
      ) : null}
      <Text style={styles.note}>
        No hay un estado de “sin pago” en el esquema. Esta solicitud no cobra.
        Las fotos de inicio y fin siguen pendientes y esta pantalla no abre Storage.
      </Text>
    </ScreenScaffold>
  );
}

const BOOKING_STATUSES = new Set<BookingStatus>([
  'DRAFT',
  'REQUESTED',
  'PENDING_REQUIREMENTS',
  'PENDING_APPROVAL',
  'APPROVED',
  'CONFIRMED',
  'ACTIVE',
  'COMPLETED',
  'REJECTED',
  'CANCELLED',
  'EXPIRED',
  'DISPUTED',
]);

function isBookingStatus(status: string | null): status is BookingStatus {
  return status !== null && BOOKING_STATUSES.has(status as BookingStatus);
}

const styles = StyleSheet.create({
  equine: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 4,
  },
  body: {
    color: colors.text,
    fontSize: 16,
    marginBottom: 4,
  },
  note: {
    color: colors.muted,
    fontSize: 14,
    lineHeight: 20,
    marginBottom: 12,
  },
  message: {
    marginBottom: 12,
    color: '#9d1c1c',
    fontSize: 14,
    lineHeight: 20,
  },
  primaryButton: {
    minHeight: 48,
    marginTop: 8,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: colors.text,
  },
  primaryButtonText: {
    color: colors.surface,
    fontSize: 16,
    fontWeight: '600',
  },
});
