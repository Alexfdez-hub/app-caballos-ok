import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import type { VerificationScreenProps } from '../app/navigation/types';
import { useVerification } from '../features/verification/useVerification';
import type { EquineRelationView } from '../features/verification/types';

function RelationList({
  rows,
  emptyTitle,
  emptyDescription,
}: {
  rows: EquineRelationView[];
  emptyTitle: string;
  emptyDescription: string;
}) {
  if (rows.length === 0) {
    return (
      <EmptyStateCard title={emptyTitle} description={emptyDescription} />
    );
  }

  return (
    <>
      {rows.map((row) => (
        <Text key={row.effectiveId} style={styles.relationLine}>
          {row.displayName}
          {' · '}
          {row.relationLabel}
          {' · '}
          {row.statusLabel}
        </Text>
      ))}
    </>
  );
}

export default function VerificationScreen(_props: VerificationScreenProps) {
  const {
    hasSession,
    isLoading,
    errorMessage,
    notice,
    isSubmitting,
    spain,
    ownerships,
    management,
    refresh,
    requestSpainIdentity,
  } = useVerification();

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Verificación"
        subtitle="Estado de confianza de tu identidad. No abre publicación, reservas ni pagos."
      />

      {!hasSession ? (
        <Text accessibilityRole="alert" style={styles.message}>
          Inicia sesión para consultar tu verificación.
        </Text>
      ) : null}

      {hasSession && isLoading ? (
        <ActivityIndicator color={colors.text} />
      ) : null}

      {hasSession && errorMessage ? (
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

      {hasSession && !isLoading && !errorMessage ? (
        <>
          <SectionCard title="Verificación de identidad">
            <Text style={styles.meta}>Mercado: {spain.marketLabel}</Text>
            <Text style={styles.status}>{spain.statusLabel}</Text>
            <Text style={styles.body}>
              La revisión de identidad sigue siendo manual. Crear una solicitud
              no verifica tu identidad, no sustituye un futuro proceso KYC, no
              pide documentación y no habilita publicación, reservas ni pagos.
            </Text>
            {notice ? <Text style={styles.notice}>{notice}</Text> : null}
            {spain.canRequest ? (
              <Pressable
                accessibilityRole="button"
                disabled={isSubmitting}
                onPress={() => {
                  void requestSpainIdentity();
                }}
                style={({ pressed }) => [
                  styles.primaryButton,
                  pressed && styles.buttonPressed,
                  isSubmitting && styles.buttonDisabled,
                ]}
              >
                {isSubmitting ? (
                  <ActivityIndicator color={colors.surface} />
                ) : (
                  <Text style={styles.primaryButtonText}>
                    Solicitar verificación
                  </Text>
                )}
              </Pressable>
            ) : null}
          </SectionCard>

          <SectionCard title="Propiedad de equinos">
            <RelationList
              emptyDescription="No hay una propiedad efectiva asociada a tu identidad."
              emptyTitle="Sin propiedades"
              rows={ownerships}
            />
          </SectionCard>

          <SectionCard title="Responsabilidad sobre equinos">
            <RelationList
              emptyDescription="No hay una responsabilidad de gestión asociada a tu identidad."
              emptyTitle="Sin responsabilidades"
              rows={management}
            />
          </SectionCard>

          <Pressable
            accessibilityRole="button"
            disabled={isSubmitting}
            onPress={() => {
              void refresh();
            }}
            style={({ pressed }) => [
              styles.secondaryButton,
              pressed && styles.buttonPressed,
              isSubmitting && styles.buttonDisabled,
            ]}
          >
            <Text style={styles.secondaryButtonText}>Actualizar</Text>
          </Pressable>
        </>
      ) : null}
    </ScreenScaffold>
  );
}

const styles = StyleSheet.create({
  meta: {
    color: colors.muted,
    fontSize: 14,
  },
  status: {
    marginTop: 8,
    color: colors.text,
    fontSize: 18,
    fontWeight: '700',
  },
  body: {
    marginTop: 8,
    color: colors.muted,
    fontSize: 14,
    lineHeight: 20,
  },
  notice: {
    marginTop: 12,
    color: colors.text,
    fontSize: 14,
    lineHeight: 20,
  },
  relationLine: {
    marginTop: 8,
    color: colors.text,
    fontSize: 15,
    lineHeight: 22,
  },
  message: {
    marginBottom: 12,
    color: colors.text,
    fontSize: 15,
    lineHeight: 22,
  },
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
