import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';

import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import {
  consentDisplayStatus,
  consentStatusLabel,
  isConsentCurrentlyValid,
} from '../features/guardians/consentStatus';
import { useGuardians } from '../features/guardians/useGuardians';
import type {
  GuardianConsent,
  GuardianRelationship,
  GuardianVerificationStatus,
} from '../features/guardians/types';

function statusLabel(status: GuardianVerificationStatus): string {
  switch (status) {
    case 'PENDING':
      return 'Pendiente de verificación';
    case 'VERIFIED':
      return 'Verificada';
    case 'REJECTED':
      return 'Rechazada';
    case 'REVOKED':
      return 'Revocada';
    case 'EXPIRED':
      return 'Caducada';
  }
}

function minorLabel(relationship: GuardianRelationship): string {
  const name = [relationship.minorFirstName, relationship.minorLastName]
    .filter(Boolean)
    .join(' ');
  return name || 'Menor vinculado';
}

function consentsFor(
  relationship: GuardianRelationship,
  consents: GuardianConsent[],
) {
  return consents.filter(
    (consent) => consent.guardianRelationshipId === relationship.id,
  );
}

export default function GuardianRelationshipsScreen() {
  const {
    relationships,
    consents,
    isLoading,
    isMutating,
    errorMessage,
    revoke,
  } = useGuardians();

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Tutor y menores"
        subtitle="Relaciones y consentimientos de tu identidad. La verificación no se puede hacer en la app."
      />

      {isLoading ? (
        <ActivityIndicator color={colors.text} />
      ) : null}

      {errorMessage ? (
        <Text accessibilityRole="alert" style={styles.message}>
          {errorMessage}
        </Text>
      ) : null}

      {!isLoading && relationships.length === 0 ? (
        <SectionCard>
          <EmptyStateCard
            title="No hay relaciones de tutor"
            description="Las relaciones tutor-menor no se crean ni se verifican desde esta aplicación. Cuando existan, aparecerán aquí."
          />
        </SectionCard>
      ) : null}

      {relationships.map((relationship) => {
        const relatedConsents = consentsFor(relationship, consents);
        const canRevoke =
          relationship.verificationStatus === 'VERIFIED' &&
          relatedConsents.some((consent) => isConsentCurrentlyValid(consent));

        return (
          <SectionCard key={relationship.id} title={minorLabel(relationship)}>
            <Text style={styles.meta}>{statusLabel(relationship.verificationStatus)}</Text>
            <Text style={styles.hint}>
              El consentimiento de actividad es distinto de aceptar una política de tutor.
            </Text>

            {relatedConsents.length === 0 ? (
              <EmptyStateCard
                title="Sin consentimientos"
                description={
                  relationship.verificationStatus === 'VERIFIED'
                    ? 'No hay consentimiento de actividad registrado. Hace falta una regla de mercado vigente y, si aplica, la política de tutor aceptada. No se puede conceder sin esos datos.'
                    : 'Solo una relación verificada puede recibir consentimiento.'
                }
              />
            ) : (
              relatedConsents.map((consent) => (
                <View key={consent.id} style={styles.consentRow}>
                  <Text style={styles.consentLabel}>
                    {consent.consentType} · {consent.scopeType}
                  </Text>
                  <Text style={styles.meta}>
                    {consentStatusLabel(consentDisplayStatus(consent))}
                  </Text>
                </View>
              ))
            )}

            {canRevoke ? (
              <Pressable
                accessibilityRole="button"
                disabled={isMutating}
                onPress={() => {
                  const active = relatedConsents.find((consent) =>
                    isConsentCurrentlyValid(consent),
                  );
                  if (active) {
                    void revoke(active.id);
                  }
                }}
                style={({ pressed }) => [
                  styles.secondaryButton,
                  pressed && styles.buttonPressed,
                  isMutating && styles.buttonDisabled,
                ]}
              >
                {isMutating ? (
                  <ActivityIndicator color={colors.text} />
                ) : (
                  <Text style={styles.secondaryButtonText}>
                    Revocar consentimiento activo
                  </Text>
                )}
              </Pressable>
            ) : null}
          </SectionCard>
        );
      })}
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
  meta: {
    color: colors.muted,
    fontSize: 14,
    fontWeight: '600',
  },
  hint: {
    marginTop: 8,
    marginBottom: 12,
    color: colors.muted,
    fontSize: 13,
    lineHeight: 18,
  },
  consentRow: {
    marginBottom: 8,
  },
  consentLabel: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
  },
  secondaryButton: {
    minHeight: 50,
    marginTop: 12,
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
  secondaryButtonText: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
});
