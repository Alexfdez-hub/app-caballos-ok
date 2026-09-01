import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import type { PassportScreenProps } from '../app/navigation/types';
import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { MenuRow } from '../app/ui/MenuRow';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import { useIdentity } from '../features/identity/useIdentity';
import { useRiderProfile } from '../features/riders/useRiderProfile';

const DEFERRED_PASSPORT_SECTIONS = [
  {
    label: 'Disciplinas',
    description: 'Aún no hay especialidades. Se añadirán en una fase posterior.',
  },
  {
    label: 'Galopes / cualificaciones',
    description:
      'No hay niveles ni equivalencias. Un perfil de jinete no acredita cualificación.',
  },
  {
    label: 'Evaluaciones de hípicas',
    description:
      'Todavía no hay evaluaciones de centro. El perfil no equivale a una evaluación.',
  },
  {
    label: 'Autorizaciones',
    description:
      'No hay autorizaciones de equino. El perfil no concede permiso de monta.',
  },
  {
    label: 'Sesiones verificadas',
    description: 'Aún no hay historial de sesiones ni Session Zero.',
  },
  {
    label: 'Horas de monta',
    description: 'El tiempo de monta no se calcula todavía.',
  },
  {
    label: 'Equinos montados',
    description: 'No hay relación con equinos en esta fase.',
  },
  {
    label: 'Centros visitados',
    description: 'Los centros no están implementados todavía.',
  },
] as const;

function visibilityCopy(value: 'PRIVATE' | 'PUBLIC') {
  return value === 'PUBLIC'
    ? 'Público (intención guardada; no visible a otras personas todavía)'
    : 'Privado';
}

export default function EquestrianPassportScreen({
  navigation,
}: PassportScreenProps) {
  const { identity } = useIdentity();
  const { profile, isLoading, errorMessage, refresh } = useRiderProfile();
  const fullName = [identity?.firstName, identity?.lastName]
    .filter(Boolean)
    .join(' ');

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Pasaporte ecuestre"
        subtitle="Tu perfil de jinete y los apartados que todavía no existen."
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
              styles.retryButton,
              pressed && styles.buttonPressed,
            ]}
          >
            <Text style={styles.primaryButtonText}>Reintentar</Text>
          </Pressable>
        </>
      ) : null}

      <SectionCard title={fullName || 'Identidad'}>
        {profile ? (
          <>
            <MenuRow
              description={profile.bio || 'Sin biografía'}
              label="Biografía"
              status="readonly"
            />
            <MenuRow
              description={
                profile.experienceStartYear
                  ? String(profile.experienceStartYear)
                  : 'Sin año registrado'
              }
              label="Inicio de experiencia"
              status="readonly"
            />
            <MenuRow
              description={visibilityCopy(profile.profileVisibility)}
              isLast
              label="Visibilidad"
              status="readonly"
            />
            <Pressable
              accessibilityRole="button"
              onPress={() => navigation.navigate('EditRiderProfile')}
              style={({ pressed }) => [
                styles.primaryButton,
                pressed && styles.buttonPressed,
              ]}
            >
              <Text style={styles.primaryButtonText}>Editar perfil de jinete</Text>
            </Pressable>
          </>
        ) : !isLoading && !errorMessage ? (
            <>
              <EmptyStateCard
                description="Puedes crear tu perfil de jinete. Eso no acepta la política de jinete, no sustituye el consentimiento de tutor y no acredita nivel ni autorización."
                title="Todavía no hay perfil de jinete"
              />
              <Pressable
                accessibilityRole="button"
                onPress={() => navigation.navigate('EditRiderProfile')}
                style={({ pressed }) => [
                  styles.primaryButton,
                  pressed && styles.buttonPressed,
                ]}
              >
                <Text style={styles.primaryButtonText}>
                  Crear perfil de jinete
                </Text>
              </Pressable>
            </>
        ) : null}
      </SectionCard>

      <SectionCard title="Aún no implementado">
        {DEFERRED_PASSPORT_SECTIONS.map((section, index) => (
          <MenuRow
            key={section.label}
            description={section.description}
            isLast={index === DEFERRED_PASSPORT_SECTIONS.length - 1}
            label={section.label}
            status="comingSoon"
          />
        ))}
      </SectionCard>
    </ScreenScaffold>
  );
}

const styles = StyleSheet.create({
  message: {
    marginBottom: 16,
    color: '#9d1c1c',
    fontSize: 14,
  },
  retryButton: {
    marginBottom: 16,
  },
  primaryButton: {
    minHeight: 50,
    marginTop: 16,
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
});
