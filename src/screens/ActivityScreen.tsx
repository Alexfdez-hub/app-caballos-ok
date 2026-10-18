import { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import {
  formatActivityRange,
  groupActivity,
} from '../features/activity/activityBuckets';
import {
  bookingStatusLabel,
  callerRelationLabel,
} from '../features/activity/labels';
import {
  sessionActionForRow,
  sessionPressPlan,
  sessionPressResult,
} from '../features/activity/sessionActions';
import { presentAccountSnapshot } from '../features/activity/accountSnapshot';
import { useMyActivity } from '../features/activity/useMyActivity';
import type { ActivityBooking } from '../features/activity/types';
import { useAuth } from '../features/auth/useAuth';
import { userFacingMutationMessage } from '../features/activity/activityErrors';
import {
  beginExclusivePress,
  endExclusivePress,
  idleExclusivePress,
  mayPublishExclusiveResult,
  type ExclusivePress,
} from '../features/activity/exclusivePress';
import {
  confirmBooking,
  endBookedSession,
  startBookedSession,
} from '../features/explore/exploreService';
import { formatOfferRange } from '../features/explore/formatOfferRange';
import type { ConfirmableBooking } from '../features/explore/types';
import { useConfirmQueue } from '../features/explore/useConfirmQueue';

function ActivityRows({
  rows,
  onChanged,
  sessionActions,
  userIdRef,
  screenActiveRef,
}: {
  rows: ActivityBooking[];
  onChanged: () => void;
  sessionActions: boolean;
  userIdRef: { current: string | null };
  screenActiveRef: { current: boolean };
}) {
  return (
    <>
      {rows.map((row) => {
        const action = sessionActions ? sessionActionForRow(row) : null;
        return (
          <SectionCard key={row.bookingId} title={bookingStatusLabel(row.bookingStatus)}>
            <Text style={styles.when}>
              {formatActivityRange(row.startsAt, row.endsAt)}
            </Text>
            <Text style={styles.relation}>{callerRelationLabel(row.callerRelation)}</Text>
            {row.sessionStatus ? (
              <Text style={styles.session}>Sesión: {row.sessionStatus}</Text>
            ) : null}
            {action === 'start' ? (
              <SessionButton
                label="Iniciar actividad"
                userIdRef={userIdRef}
                screenActiveRef={screenActiveRef}
                onPress={() => startBookedSession(row.bookingId)}
                onChanged={onChanged}
              />
            ) : null}
            {action === 'end' ? (
              <SessionButton
                label="Finalizar actividad"
                userIdRef={userIdRef}
                screenActiveRef={screenActiveRef}
                onPress={() => endBookedSession(row.sessionId as string)}
                onChanged={onChanged}
              />
            ) : null}
          </SectionCard>
        );
      })}
    </>
  );
}

function SessionButton({
  label,
  onPress,
  onChanged,
  userIdRef,
  screenActiveRef,
}: {
  label: string;
  onPress: () => Promise<string>;
  onChanged: () => void;
  userIdRef: { current: string | null };
  screenActiveRef: { current: boolean };
}) {
  const pressRef = useRef<ExclusivePress>(idleExclusivePress());
  const [message, setMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  return (
    <>
      {message ? (
        <Text accessibilityRole="alert" style={styles.message}>
          {message}
        </Text>
      ) : null}
      <Pressable
        accessibilityRole="button"
        disabled={pending}
        onPress={() => {
          if (sessionPressPlan(pressRef.current.held) === 'ignore') {
            return;
          }
          const begun = beginExclusivePress(pressRef.current);
          pressRef.current = begun.state;
          if (begun.generation === null) {
            return;
          }
          const generation = begun.generation;
          const requestedUserId = userIdRef.current;
          setPending(true);
          setMessage(null);
          void onPress()
            .then(() => {
              if (
                mayPublishExclusiveResult(
                  pressRef.current,
                  generation,
                  screenActiveRef.current,
                  requestedUserId,
                  userIdRef.current,
                ) &&
                sessionPressResult(true) === 'refresh'
              ) {
                onChanged();
              }
            })
            .catch((error: unknown) => {
              if (
                mayPublishExclusiveResult(
                  pressRef.current,
                  generation,
                  screenActiveRef.current,
                  requestedUserId,
                  userIdRef.current,
                ) &&
                sessionPressResult(false) === 'message'
              ) {
                setMessage(userFacingMutationMessage(error));
              }
            })
            .finally(() => {
              pressRef.current = endExclusivePress(pressRef.current, generation);
              setPending(pressRef.current.held);
            });
        }}
        style={styles.primaryButton}
      >
        <Text style={styles.primaryButtonText}>{label}</Text>
      </Pressable>
    </>
  );
}

export default function ActivityScreen() {
  const { session } = useAuth();
  const userId = session?.user.id ?? null;
  const userIdRef = useRef(userId);
  const screenActiveRef = useRef(false);
  userIdRef.current = userId;
  const activity = useMyActivity(userId);
  const confirmQueue = useConfirmQueue(userId);
  const activityView = presentAccountSnapshot(activity.read, userId);
  const confirmView = presentAccountSnapshot(confirmQueue.read, userId);
  const grouped = groupActivity(activityView.rows, new Date());
  const activitySettled = activityView.owned && !activityView.isLoading;
  const confirmSettled = confirmView.owned && !confirmView.isLoading;

  useFocusEffect(
    useCallback(() => {
      screenActiveRef.current = true;
      return () => {
        screenActiveRef.current = false;
      };
    }, []),
  );

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Actividad"
        subtitle="Tus reservas, solicitudes y sesiones."
      />

      {activityView.isLoading ? <ActivityIndicator color={colors.text} /> : null}

      {activityView.owned && activityView.errorMessage ? (
        <Text accessibilityRole="alert" style={styles.message}>
          {activityView.errorMessage}
        </Text>
      ) : null}

      {activitySettled ? (
        <Pressable
          accessibilityRole="button"
          onPress={() => {
            void activity.refresh();
          }}
          style={({ pressed }) => [
            styles.primaryButton,
            pressed && styles.buttonPressed,
          ]}
        >
          <Text style={styles.primaryButtonText}>
            {activityView.errorMessage ? 'Reintentar' : 'Actualizar'}
          </Text>
        </Pressable>
      ) : null}

      <SectionCard title="Próximas">
        {activitySettled && !activityView.errorMessage && grouped.upcoming.length === 0 ? (
          <EmptyStateCard
            title="No tienes próximas actividades"
            description="Cuando una reserva quede confirmada, aparecerá aquí."
          />
        ) : (
          <ActivityRows
            rows={activityView.owned ? grouped.upcoming : []}
            sessionActions
            userIdRef={userIdRef}
            screenActiveRef={screenActiveRef}
            onChanged={() => void activity.refresh()}
          />
        )}
      </SectionCard>

      <SectionCard title="Puedes confirmar">
        <Text style={styles.note}>
          Solo aparecen solicitudes ya aprobadas si tu cuenta tiene la
          autoridad de reservas del centro. Confirmar no es un pago.
        </Text>
        {confirmView.owned && confirmView.errorMessage ? (
          <Text accessibilityRole="alert" style={styles.message}>
            {confirmView.errorMessage}
          </Text>
        ) : null}
        {confirmSettled && confirmView.rows.length === 0 ? (
          <EmptyStateCard
            title="Nada pendiente de tu confirmación"
            description="Si no gestionas reservas de un centro, esta lista permanece vacía."
          />
        ) : (
          (confirmView.owned ? confirmView.rows : []).map((booking) => (
            <ConfirmRow
              key={booking.bookingId}
              booking={booking}
              userIdRef={userIdRef}
              screenActiveRef={screenActiveRef}
              onChanged={() => {
                void confirmQueue.refresh();
                void activity.refresh();
              }}
            />
          ))
        )}
      </SectionCard>

      <SectionCard title="Solicitudes">
        {activitySettled && !activityView.errorMessage && grouped.openRequests.length === 0 ? (
          <EmptyStateCard
            title="No hay solicitudes abiertas"
            description="Las peticiones de reserva pendientes de confirmación se mostrarán en esta lista."
          />
        ) : (
          <ActivityRows
            rows={activityView.owned ? grouped.openRequests : []}
            sessionActions={false}
            userIdRef={userIdRef}
            screenActiveRef={screenActiveRef}
            onChanged={() => void activity.refresh()}
          />
        )}
      </SectionCard>

      <SectionCard title="Tu agenda">
        <Text style={styles.note}>
          Estas horas son tus reservas. No son la ocupación del equino ni la
          disponibilidad del centro.
        </Text>
        {activitySettled && !activityView.errorMessage && grouped.upcoming.length === 0 ? (
          <EmptyStateCard
            title="Todavía no hay reservas confirmadas"
            description="La agenda muestra solo las reservas confirmadas o en curso de tu cuenta."
          />
        ) : (
          <ActivityRows
            rows={activityView.owned ? grouped.upcoming : []}
            sessionActions={false}
            userIdRef={userIdRef}
            screenActiveRef={screenActiveRef}
            onChanged={() => void activity.refresh()}
          />
        )}
      </SectionCard>

      <SectionCard title="Cerradas">
        {activitySettled && !activityView.errorMessage && grouped.closed.length === 0 ? (
          <EmptyStateCard
            title="No hay reservas cerradas"
            description="Las canceladas, rechazadas, caducadas o en disputa aparecen aquí."
          />
        ) : (
          <ActivityRows
            rows={activityView.owned ? grouped.closed : []}
            sessionActions={false}
            userIdRef={userIdRef}
            screenActiveRef={screenActiveRef}
            onChanged={() => void activity.refresh()}
          />
        )}
      </SectionCard>

      <SectionCard title="Historial">
        {activitySettled && !activityView.errorMessage && grouped.history.length === 0 ? (
          <EmptyStateCard
            title="Aún no hay historial"
            description="Las sesiones que completes aparecerán aquí."
          />
        ) : (
          <ActivityRows
            rows={activityView.owned ? grouped.history : []}
            sessionActions={false}
            userIdRef={userIdRef}
            screenActiveRef={screenActiveRef}
            onChanged={() => void activity.refresh()}
          />
        )}
        <Text style={styles.note}>
          Sesión Cero no aparece en esta lista. No hay una lectura limitada al
          llamador para esas filas. Las fotos de inicio y de fin siguen
          pendientes: esta pantalla no abre Storage.
        </Text>
      </SectionCard>
    </ScreenScaffold>
  );
}

function ConfirmRow({
  booking,
  onChanged,
  userIdRef,
  screenActiveRef,
}: {
  booking: ConfirmableBooking;
  onChanged: () => void;
  userIdRef: { current: string | null };
  screenActiveRef: { current: boolean };
}) {
  const pressRef = useRef<ExclusivePress>(idleExclusivePress());
  const [message, setMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  return (
    <SectionCard title={booking.centerName}>
      <Text style={styles.when}>{booking.equineName}</Text>
      <Text style={styles.relation}>{booking.serviceName}</Text>
      <Text style={styles.session}>
        {formatOfferRange(booking.startsAt, booking.endsAt, null)}
      </Text>
      {message ? (
        <Text accessibilityRole="alert" style={styles.message}>
          {message}
        </Text>
      ) : null}
      <Pressable
        accessibilityRole="button"
        disabled={pending}
        onPress={() => {
          if (sessionPressPlan(pressRef.current.held) === 'ignore') {
            return;
          }
          const begun = beginExclusivePress(pressRef.current);
          pressRef.current = begun.state;
          if (begun.generation === null) {
            return;
          }
          const generation = begun.generation;
          const requestedUserId = userIdRef.current;
          setPending(true);
          setMessage(null);
          void confirmBooking(booking.bookingId)
            .then(() => {
              if (
                mayPublishExclusiveResult(
                  pressRef.current,
                  generation,
                  screenActiveRef.current,
                  requestedUserId,
                  userIdRef.current,
                )
              ) {
                onChanged();
              }
            })
            .catch((error: unknown) => {
              if (
                mayPublishExclusiveResult(
                  pressRef.current,
                  generation,
                  screenActiveRef.current,
                  requestedUserId,
                  userIdRef.current,
                )
              ) {
                setMessage(userFacingMutationMessage(error));
              }
            })
            .finally(() => {
              pressRef.current = endExclusivePress(pressRef.current, generation);
              setPending(pressRef.current.held);
            });
        }}
        style={styles.primaryButton}
      >
        <Text style={styles.primaryButtonText}>Confirmar reserva</Text>
      </Pressable>
    </SectionCard>
  );
}

const styles = StyleSheet.create({
  message: {
    marginBottom: 16,
    color: '#9d1c1c',
    fontSize: 14,
    lineHeight: 20,
  },
  primaryButton: {
    minHeight: 50,
    marginBottom: 16,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: colors.text,
  },
  buttonPressed: {
    opacity: 0.8,
  },
  primaryButtonText: {
    color: colors.surface,
    fontSize: 16,
    fontWeight: '600',
  },
  when: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
  },
  relation: {
    marginTop: 8,
    color: colors.muted,
    fontSize: 14,
    lineHeight: 20,
  },
  session: {
    marginTop: 8,
    color: colors.muted,
    fontSize: 13,
  },
  note: {
    marginBottom: 12,
    color: colors.muted,
    fontSize: 13,
    lineHeight: 18,
  },
});
