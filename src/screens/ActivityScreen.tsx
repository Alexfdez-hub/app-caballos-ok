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

function ActivityRows({ rows }: { rows: ActivityBooking[] }) {
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
        </SectionCard>
      ))}
    </>
  );
}

export default function ActivityScreen() {
  const { rows, isLoading, errorMessage, refresh } = useMyActivity();
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
          <ActivityRows rows={grouped.upcoming} />
        )}
      </SectionCard>

      <SectionCard title="Solicitudes">
        {!isLoading && !errorMessage && grouped.openRequests.length === 0 ? (
          <EmptyStateCard
            title="No hay solicitudes abiertas"
            description="Las peticiones de reserva pendientes de confirmación se mostrarán en esta lista."
          />
        ) : (
          <ActivityRows rows={grouped.openRequests} />
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
          <ActivityRows rows={grouped.upcoming} />
        )}
      </SectionCard>

      <SectionCard title="Historial">
        {!isLoading && !errorMessage && grouped.history.length === 0 ? (
          <EmptyStateCard
            title="Aún no hay historial"
            description="Las sesiones que completes aparecerán aquí."
          />
        ) : (
          <ActivityRows rows={grouped.history} />
        )}
        <Text style={styles.note}>
          Sesión Cero no aparece en esta lista. No hay una lectura limitada al
          llamador para esas filas.
        </Text>
      </SectionCard>
    </ScreenScaffold>
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
