import { useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

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
import { useMyActivity } from '../features/activity/useMyActivity';
import type { ActivityBooking } from '../features/activity/types';
import { useAuth } from '../features/auth/useAuth';
import { userFacingExploreMessage } from '../features/explore/exploreErrors';
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
}: {
  rows: ActivityBooking[];
  onChanged: () => void;
}) {
  return (
    <>
      {rows.map((row) => (
        <SectionCard key={row.bookingId} title={bookingStatusLabel(row.bookingStatus)}>
          <Text style={styles.when}>
            {formatActivityRange(row.startsAt, row.endsAt)}
          </Text>
          <Text style={styles.relation}>{callerRelationLabel(row.callerRelation)}</Text>
          {row.sessionStatus ? (
            <Text style={styles.session}>Sesión: {row.sessionStatus}</Text>
          ) : null}
          {row.bookingStatus === 'CONFIRMED' && !row.sessionId ? (
            <SessionButton
              label="Iniciar actividad"
              onPress={() => startBookedSession(row.bookingId)}
              onChanged={onChanged}
            />
          ) : null}
          {row.sessionStatus === 'ACTIVE' && row.sessionId ? (
            <SessionButton
              label="Finalizar actividad"
              onPress={() => endBookedSession(row.sessionId as string)}
              onChanged={onChanged}
            />
          ) : null}
        </SectionCard>
      ))}
    </>
  );
}

function SessionButton({
  label,
  onPress,
  onChanged,
}: {
  label: string;
  onPress: () => Promise<string>;
  onChanged: () => void;
}) {
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
          if (pending) {
            return;
          }
          setPending(true);
          setMessage(null);
          void onPress()
            .then(() => {
              onChanged();
            })
            .catch((error: unknown) => {
              setMessage(userFacingExploreMessage(error));
            })
            .finally(() => {
              setPending(false);
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
  const { rows, isLoading, errorMessage, refresh } = useMyActivity(userId);
  const confirmQueue = useConfirmQueue(userId);
  const grouped = groupActivity(rows, new Date());

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Actividad"
        subtitle="Tus reservas, solicitudes y sesiones."
      />

      {isLoading ? <ActivityIndicator color={colors.text} /> : null}

      {errorMessage ? (
        <Text accessibilityRole="alert" style={styles.message}>
          {errorMessage}
        </Text>
      ) : null}

      {!isLoading ? (
        <Pressable
          accessibilityRole="button"
          onPress={() => {
            void refresh();
          }}
          style={({ pressed }) => [
            styles.primaryButton,
            pressed && styles.buttonPressed,
          ]}
        >
          <Text style={styles.primaryButtonText}>
            {errorMessage ? 'Reintentar' : 'Actualizar'}
          </Text>
        </Pressable>
      ) : null}

      <SectionCard title="Próximas">
        {!isLoading && !errorMessage && grouped.upcoming.length === 0 ? (
          <EmptyStateCard
            title="No tienes próximas actividades"
            description="Cuando una reserva quede confirmada, aparecerá aquí."
          />
        ) : (
          <ActivityRows rows={grouped.upcoming} onChanged={() => void refresh()} />
        )}
      </SectionCard>

      <SectionCard title="Puedes confirmar">
        <Text style={styles.note}>
          Solo aparecen solicitudes ya aprobadas si tu cuenta tiene la
          autoridad de reservas del centro. Confirmar no es un pago.
        </Text>
        {confirmQueue.errorMessage ? (
          <Text accessibilityRole="alert" style={styles.message}>
            {confirmQueue.errorMessage}
          </Text>
        ) : null}
        {!confirmQueue.isLoading && confirmQueue.rows.length === 0 ? (
          <EmptyStateCard
            title="Nada pendiente de tu confirmación"
            description="Si no gestionas reservas de un centro, esta lista permanece vacía."
          />
        ) : (
          confirmQueue.rows.map((booking) => (
            <ConfirmRow
              key={booking.bookingId}
              booking={booking}
              onChanged={() => {
                void confirmQueue.refresh();
                void refresh();
              }}
            />
          ))
        )}
      </SectionCard>

      <SectionCard title="Solicitudes">
        {!isLoading && !errorMessage && grouped.openRequests.length === 0 ? (
          <EmptyStateCard
            title="No hay solicitudes abiertas"
            description="Las peticiones de reserva pendientes de confirmación se mostrarán en esta lista."
          />
        ) : (
          <ActivityRows rows={grouped.openRequests} onChanged={() => void refresh()} />
        )}
      </SectionCard>

      <SectionCard title="Tu agenda">
        <Text style={styles.note}>
          Estas horas son tus reservas. No son la ocupación del equino ni la
          disponibilidad del centro.
        </Text>
        {!isLoading && !errorMessage && grouped.upcoming.length === 0 ? (
          <EmptyStateCard
            title="Todavía no hay reservas confirmadas"
            description="La agenda muestra solo las reservas confirmadas o en curso de tu cuenta."
          />
        ) : (
          <ActivityRows rows={grouped.upcoming} onChanged={() => void refresh()} />
        )}
      </SectionCard>

      <SectionCard title="Cerradas">
        {!isLoading && !errorMessage && grouped.closed.length === 0 ? (
          <EmptyStateCard
            title="No hay reservas cerradas"
            description="Las canceladas, rechazadas, caducadas o en disputa aparecen aquí."
          />
        ) : (
          <ActivityRows rows={grouped.closed} onChanged={() => void refresh()} />
        )}
      </SectionCard>

      <SectionCard title="Historial">
        {!isLoading && !errorMessage && grouped.history.length === 0 ? (
          <EmptyStateCard
            title="Aún no hay historial"
            description="Las sesiones que completes aparecerán aquí."
          />
        ) : (
          <ActivityRows rows={grouped.history} onChanged={() => void refresh()} />
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
}: {
  booking: ConfirmableBooking;
  onChanged: () => void;
}) {
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
          if (pending) {
            return;
          }
          setPending(true);
          setMessage(null);
          void confirmBooking(booking.bookingId)
            .then(() => {
              onChanged();
            })
            .catch((error: unknown) => {
              setMessage(userFacingExploreMessage(error));
            })
            .finally(() => {
              setPending(false);
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
