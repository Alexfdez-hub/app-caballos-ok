import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import type { MyEquinesScreenProps } from '../app/navigation/types';
import { equineTypeLabel } from '../features/equines/labels';
import { useMyEquines } from '../features/equines/useMyEquines';

export default function MyEquinesScreen({ navigation }: MyEquinesScreenProps) {
  const { rows, isLoading, errorMessage, refresh } = useMyEquines();

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Mis equinos"
        subtitle="Equinos de tu identidad. Una membresía de centro o una tutela no crean esta relación."
      />

      <Pressable
        accessibilityRole="button"
        onPress={() => navigation.navigate('CreateEquine')}
        style={({ pressed }) => [
          styles.primaryButton,
          pressed && styles.buttonPressed,
        ]}
      >
        <Text style={styles.primaryButtonText}>Añadir equino</Text>
      </Pressable>

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
              styles.secondaryButton,
              pressed && styles.buttonPressed,
            ]}
          >
            <Text style={styles.secondaryButtonText}>Reintentar</Text>
          </Pressable>
        </>
      ) : null}

      {!isLoading && !errorMessage && rows.length === 0 ? (
        <SectionCard>
          <EmptyStateCard
            title="Sin equinos"
            description="Todavía no hay un equino vinculado a tu identidad. Puedes crear uno si tu cuenta es de una persona adulta con mercado."
          />
        </SectionCard>
      ) : null}

      {rows.map((row) => (
        <Pressable
          key={row.equineId}
          accessibilityRole="button"
          onPress={() =>
            navigation.navigate('EquineDetail', { equineId: row.equineId })
          }
        >
          <SectionCard title={row.equineName}>
            <Text style={styles.roleLine}>
              {equineTypeLabel(row.equineType)}
              {row.isOwner ? ' · Propiedad' : ''}
              {row.isPrimaryManager ? ' · Gestor principal' : ''}
            </Text>
          </SectionCard>
        </Pressable>
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
  secondaryButton: {
    minHeight: 50,
    marginBottom: 16,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: colors.border,
  },
  buttonPressed: {
    opacity: 0.8,
  },
  primaryButtonText: {
    color: colors.surface,
    fontSize: 16,
    fontWeight: '600',
  },
  secondaryButtonText: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
  roleLine: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
  },
});
