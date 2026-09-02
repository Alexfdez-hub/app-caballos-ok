import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import {
  equineTypeLabel,
  effectiveRelationStatusLabel,
} from '../features/equines/labels';
import { useMyEquineOwnerships } from '../features/equines/useMyEquineOwnerships';

export default function MyEquinesScreen() {
  const { rows, isLoading, errorMessage, refresh } = useMyEquineOwnerships();

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Mis equinos"
        subtitle="Participaciones de tu identidad. El alta, la cesión y el directorio público no están en la app."
      />

      {isLoading ? <ActivityIndicator color={colors.text} /> : null}

      {errorMessage ? (
        <>
          <Text accessibilityRole="alert" style={styles.message}>
            {errorMessage}
          </Text>
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
            <Text style={styles.primaryButtonText}>Reintentar</Text>
          </Pressable>
        </>
      ) : null}

      {!isLoading && !errorMessage && rows.length === 0 ? (
        <SectionCard>
          <EmptyStateCard
            title="Sin participaciones"
            description="Aún no figura una propiedad de equino a tu nombre. Una membresía de centro o un perfil de jinete no crean esta relación."
          />
        </SectionCard>
      ) : null}

      {rows.map((row) => (
        <SectionCard key={row.ownershipId} title={row.equineName}>
          <Text style={styles.roleLine}>
            {equineTypeLabel(row.equineType)} · {row.ownershipPercentage}% ·{' '}
            {effectiveRelationStatusLabel(row.status, row.isCurrentlyEffective)}
          </Text>
          <Text style={styles.hint}>
            Esto es propiedad, no gestión ni asignación a un centro. No publica
            el equino ni abre reservas.
          </Text>
        </SectionCard>
      ))}
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
  roleLine: {
    marginBottom: 8,
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
  },
  hint: {
    marginTop: 12,
    color: colors.muted,
    fontSize: 13,
    lineHeight: 18,
  },
});
