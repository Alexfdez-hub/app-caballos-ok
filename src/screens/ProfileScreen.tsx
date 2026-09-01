import { useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import type { ProfileScreenProps } from '../app/navigation/types';
import { colors } from '../app/ui/theme';
import { MenuRow } from '../app/ui/MenuRow';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { signOut } from '../features/auth/authService';
import { useAuth } from '../features/auth/useAuth';
import { useIdentity } from '../features/identity/useIdentity';

function formatDateOfBirth(value: string | null | undefined): string {
  if (!value) {
    return '—';
  }

  const [year, month, day] = value.split('-');

  if (!year || !month || !day) {
    return value;
  }

  return `${day}/${month}/${year}`;
}

export default function ProfileScreen({ navigation }: ProfileScreenProps) {
  const { session } = useAuth();
  const { identity } = useIdentity();
  const [isSigningOut, setIsSigningOut] = useState(false);

  const fullName = [identity?.firstName, identity?.lastName]
    .filter(Boolean)
    .join(' ');

  async function handleSignOut() {
    setIsSigningOut(true);

    try {
      await signOut();
    } finally {
      setIsSigningOut(false);
    }
  }

  return (
    <ScreenScaffold>
      <ScreenHeader title="Perfil" subtitle="Tus datos, relaciones y cuenta." />

      <SectionCard title="Datos personales">
        <MenuRow
          description={fullName || '—'}
          label="Nombre completo"
          status="readonly"
        />
        <MenuRow
          description={formatDateOfBirth(identity?.dateOfBirth)}
          label="Fecha de nacimiento"
          status="readonly"
        />
        <MenuRow
          description={session?.user.email ?? '—'}
          isLast
          label="Email de cuenta"
          status="readonly"
        />
        <Pressable
          accessibilityRole="button"
          onPress={() => navigation.navigate('EditIdentity')}
          style={({ pressed }) => [
            styles.primaryButton,
            pressed && styles.buttonPressed,
          ]}
        >
          <Text style={styles.primaryButtonText}>Editar datos básicos</Text>
        </Pressable>
      </SectionCard>

      <SectionCard title="Mi actividad ecuestre">
        <MenuRow
          description="Cuando tengas equinos propios aparecerán aquí."
          label="Mis equinos"
          status="comingSoon"
        />
        <MenuRow
          description="Cuando gestiones equinos aparecerán aquí."
          label="Equinos que gestiono"
          status="comingSoon"
        />
        <MenuRow
          description="Cuando pertenezcas a una hípica u organización aparecerá aquí."
          label="Mis centros / organizaciones"
          status="comingSoon"
        />
        <MenuRow
          description="Consulta relaciones y consentimientos reales. No se verifican desde la app."
          isLast
          label="Relaciones de tutor / menores"
          onPress={() => navigation.navigate('GuardianRelationships')}
        />
      </SectionCard>

      <SectionCard title="Cuenta y legal">
        <MenuRow
          description="Aceptaciones vigentes cuando existan políticas aplicables."
          label="Políticas y consentimientos"
          status="comingSoon"
        />
        <MenuRow
          description="Preferencias de la aplicación."
          isLast
          label="Configuración"
          status="comingSoon"
        />
      </SectionCard>

      <Pressable
        accessibilityRole="button"
        disabled={isSigningOut}
        onPress={handleSignOut}
        style={({ pressed }) => [
          styles.secondaryButton,
          pressed && styles.buttonPressed,
          isSigningOut && styles.buttonDisabled,
        ]}
      >
        {isSigningOut ? (
          <ActivityIndicator color={colors.text} />
        ) : (
          <Text style={styles.secondaryButtonText}>Cerrar sesión</Text>
        )}
      </Pressable>
    </ScreenScaffold>
  );
}

const styles = StyleSheet.create({
  primaryButton: {
    minHeight: 50,
    marginTop: 16,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: colors.text,
  },
  secondaryButton: {
    minHeight: 50,
    marginTop: 8,
    alignItems: 'center',
    justifyContent: 'center',
    borderColor: colors.text,
    borderRadius: 8,
    borderWidth: 1,
  },
  buttonPressed: {
    opacity: 0.8,
  },
  buttonDisabled: {
    opacity: 0.6,
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
});
