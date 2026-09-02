import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import {
  centerRoleLabel,
  membershipStatusLabel,
} from '../features/centers/labels';
import { useMyCenterMemberships } from '../features/centers/useMyCenterMemberships';

export default function MyCentersScreen() {
  const { groups, isLoading, errorMessage, refresh } = useMyCenterMemberships();

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Mis centros"
        subtitle="Membresías de tu identidad. El alta de centros y la asignación de roles no se hacen en la app."
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

      {!isLoading && !errorMessage && groups.length === 0 ? (
        <SectionCard>
          <EmptyStateCard
            title="Sin membresías de centro"
            description="Aún no tienes un rol en ninguna hípica. El alta de centros y la asignación de roles no están disponibles en la aplicación. Un centro no te asigna autoridad por existir."
          />
        </SectionCard>
      ) : null}

      {groups.map((group) => (
        <SectionCard key={group.centerId} title={group.centerName}>
          {group.memberships.map((membership, index) => (
            <Text
              key={membership.membershipId}
              style={[
                styles.roleLine,
                index === group.memberships.length - 1 && styles.lastRoleLine,
              ]}
            >
              {centerRoleLabel(membership.roleCode)} ·{' '}
              {membershipStatusLabel(membership.status)}
            </Text>
          ))}
          <Text style={styles.hint}>
            El rol es de este centro. No concede autoridad en otras hípicas, no
            verifica el centro y no sustituye una política de centro o de
            evaluador.
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
  lastRoleLine: {
    marginBottom: 0,
  },
  hint: {
    marginTop: 12,
    color: colors.muted,
    fontSize: 13,
    lineHeight: 18,
  },
});
