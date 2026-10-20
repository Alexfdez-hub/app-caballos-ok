import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import type { HomeScreenProps } from '../app/navigation/types';
import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { MenuRow } from '../app/ui/MenuRow';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import { presentAccountSnapshot } from '../features/activity/accountSnapshot';
import {
  formatActivityRange,
  homeActivityPanels,
  summarizeHomeActivity,
} from '../features/activity/activityBuckets';
import { bookingStatusLabel } from '../features/activity/labels';
import { useMyActivity } from '../features/activity/useMyActivity';
import { useAuth } from '../features/auth/useAuth';
import { useIdentity } from '../features/identity/useIdentity';

export default function HomeScreen({ navigation }: HomeScreenProps) {
  const { identity } = useIdentity();
  const { session } = useAuth();
  const userId = session?.user.id ?? null;
  const activity = useMyActivity(userId);
  const view = presentAccountSnapshot(activity.read, userId);
  const summary = summarizeHomeActivity(view.owned ? view.rows : [], new Date());
  const settled = view.owned && !view.isLoading;
  const panels = homeActivityPanels(settled, view.errorMessage, summary);
  const firstName = identity?.firstName ?? '';
  const openActivity = () => {
    navigation.navigate('ActivityTab', { screen: 'Activity' });
  };

  return (
    <ScreenScaffold>
      <ScreenHeader
        title={`Hola, ${firstName}`}
        subtitle="Aquí verás tu día a día ecuestre."
      />

      <SectionCard title="Próxima actividad">
        {panels.next === 'loading' ? <ActivityIndicator color={colors.text} /> : null}
        {panels.next === 'error' && view.errorMessage ? (
          <>
            <Text accessibilityRole="alert" style={styles.message}>
              {view.errorMessage}
            </Text>
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                void activity.refresh();
              }}
            >
              <Text style={styles.link}>Reintentar</Text>
            </Pressable>
          </>
        ) : null}
        {panels.next === 'next' && summary.next ? (
          <>
            <Text style={styles.title}>
              {bookingStatusLabel(summary.next.bookingStatus)}
            </Text>
            <Text style={styles.description}>
              {formatActivityRange(summary.next.startsAt, summary.next.endsAt)}
            </Text>
            <Pressable accessibilityRole="button" onPress={openActivity}>
              <Text style={styles.link}>Ver en Actividad</Text>
            </Pressable>
          </>
        ) : null}
        {panels.next === 'empty' ? (
          <EmptyStateCard
            title="No tienes próximas actividades"
            description="Cuando tengas una reserva aparecerá aquí."
          />
        ) : null}
      </SectionCard>

      <SectionCard title="Pendientes">
        {panels.pending === 'loading' ? (
          <ActivityIndicator color={colors.text} />
        ) : null}
        {panels.pending === 'error' ? (
          <Text style={styles.description}>
            Las solicitudes no se han podido leer.
          </Text>
        ) : null}
        {panels.pending === 'open' ? (
          <>
            <Text style={styles.title}>
              {summary.openRequestCount === 1
                ? 'Tienes 1 solicitud abierta'
                : `Tienes ${summary.openRequestCount} solicitudes abiertas`}
            </Text>
            <Text style={styles.description}>
              Siguen pendientes de confirmación. Confirmar no es un pago.
            </Text>
            <Pressable accessibilityRole="button" onPress={openActivity}>
              <Text style={styles.link}>Revisar solicitudes</Text>
            </Pressable>
          </>
        ) : null}
        {panels.pending === 'empty' ? (
          <EmptyStateCard
            title="No hay solicitudes pendientes"
            description="Las peticiones que esperen respuesta se mostrarán en este espacio."
          />
        ) : null}
      </SectionCard>

      <SectionCard title="Avisos">
        <EmptyStateCard
          title="No hay avisos importantes"
          description="Este MVP no tiene un canal de avisos aparte de tu actividad."
        />
      </SectionCard>

      <SectionCard title="Accesos rápidos">
        <MenuRow
          label="Explorar"
          description="Busca qué montar, hacer o aprender."
          onPress={() =>
            navigation.navigate('ExploreTab', { screen: 'Explore' })
          }
        />
        <MenuRow
          label="Actividad"
          description="Consulta reservas, solicitudes y calendario."
          onPress={() =>
            navigation.navigate('ActivityTab', { screen: 'Activity' })
          }
        />
        <MenuRow
          isLast
          label="Pasaporte"
          description="Tu recorrido e identidad ecuestre."
          onPress={() =>
            navigation.navigate('PassportTab', { screen: 'Passport' })
          }
        />
      </SectionCard>

      <SectionCard title="Cerca de ti">
        <EmptyStateCard
          title="Explora hípicas y actividades"
          description="Las franjas reservables están en Explorar. Esta sección no recomienda centros."
        />
        <MenuRow
          isLast
          label="Ir a Explorar"
          onPress={() =>
            navigation.navigate('ExploreTab', { screen: 'Explore' })
          }
        />
      </SectionCard>
    </ScreenScaffold>
  );
}

const styles = StyleSheet.create({
  message: {
    color: '#9d1c1c',
    fontSize: 14,
    lineHeight: 20,
  },
  title: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
  description: {
    marginTop: 4,
    color: colors.muted,
    fontSize: 14,
    lineHeight: 20,
  },
  link: {
    marginTop: 8,
    color: colors.accent,
    fontSize: 14,
    fontWeight: '600',
  },
});
