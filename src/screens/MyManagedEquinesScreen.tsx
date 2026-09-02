import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import {
  effectiveRelationStatusLabel,
  equineTypeLabel,
  managementRoleLabel,
} from '../features/equines/labels';
import { useMyEquineManagement } from '../features/equines/useMyEquineManagement';

export default function MyManagedEquinesScreen() {
  const { rows, isLoading, errorMessage, refresh } = useMyEquineManagement();

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Equinos que gestiono"
        subtitle="Asignaciones de gestión de tu identidad. No son propiedad ni asignación a un centro."
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
            title="Sin asignaciones de gestión"
            description="Aún no tienes un rol de gestión sobre un equino. La propiedad o una membresía de centro no conceden esta autoridad."
          />
        </SectionCard>
      ) : null}

      {rows.map((row) => (
        <SectionCard key={row.assignmentId} title={row.equineName}>
          <Text style={styles.roleLine}>
            {equineTypeLabel(row.equineType)} ·{' '}
            {managementRoleLabel(row.managementRole)} ·{' '}
            {effectiveRelationStatusLabel(row.status, row.isCurrentlyEffective)}
          </Text>
          <Text style={styles.hint}>
            La gestión no es propiedad ni permiso de centro. El alta y la
            revocación no se hacen en la app.
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
