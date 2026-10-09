import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import type { ReviewPilotScreenProps } from '../app/navigation/types';
import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import {
  caseStateLabel,
  caseTypeLabel,
  evidenceCategoryLabel,
  marketLabel,
  relationLabel,
} from '../features/verificationReview/labels';
import {
  DECISION_BLOCKED_COPY,
  EVIDENCE_INCOMPLETE_COPY,
  EVIDENCE_PRESENT_COPY,
} from '../features/verificationReview/presentation';
import { useReviewPilot } from '../features/verificationReview/useReviewPilot';

export default function ReviewPilotScreen(_props: ReviewPilotScreenProps) {
  const view = useReviewPilot();

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Revisión piloto"
        subtitle="Lectura autorizada para España. No decide ni abre documentos."
      />

      {view.kind === 'signed_out' ? (
        <Text accessibilityRole="alert" style={styles.message}>
          Inicia sesión para consultar la revisión.
        </Text>
      ) : null}

      {view.kind === 'loading' ? <ActivityIndicator color={colors.text} /> : null}

      {view.kind === 'unauthorized' ? (
        <EmptyStateCard
          title="Sin autorización"
          description="Esta cuenta no tiene una revisión vigente para España."
        />
      ) : null}

      {view.kind === 'suspended' ? (
        <EmptyStateCard
          title="Acceso cerrado"
          description="La autorización ya no está vigente. Los expedientes de esta sesión se han retirado."
        />
      ) : null}

      {view.kind === 'error' ? (
        <>
          <Text accessibilityRole="alert" style={styles.message}>
            {view.message}
          </Text>
          <Pressable
            accessibilityRole="button"
            disabled={view.actionsBlocked}
            onPress={view.refresh}
            style={styles.secondaryButton}
          >
            <Text style={styles.secondaryButtonText}>Reintentar</Text>
          </Pressable>
        </>
      ) : null}

      {view.kind === 'empty' ? (
        <EmptyStateCard
          title="Bandeja vacía"
          description="No hay expedientes abiertos en España para esta autorización."
        />
      ) : null}

      {view.kind === 'queue' ? (
        <>
          <SectionCard title="Bandeja">
            {view.items.map((item) => (
              <Pressable
                accessibilityRole="button"
                disabled={view.actionsBlocked}
                key={item.caseId}
                onPress={() => view.openCase(item.caseType, item.caseId)}
                style={styles.queueRow}
              >
                <Text style={styles.status}>
                  {caseTypeLabel(item.caseType)}
                  {' · '}
                  {caseStateLabel(item.state)}
                </Text>
                <Text style={styles.meta}>
                  {marketLabel(item.marketCountryCode)}
                  {' · '}
                  {item.updatedAt}
                </Text>
                <Text style={styles.body}>
                  {item.evidenceCategories.length === 0
                    ? 'Sin categorías de evidencia'
                    : item.evidenceCategories
                        .map((category) => evidenceCategoryLabel(category))
                        .join(', ')}
                </Text>
              </Pressable>
            ))}
          </SectionCard>

          {view.detail.kind === 'unavailable' ? (
            <EmptyStateCard
              title="Expediente no disponible"
              description="Ese expediente ya no se puede abrir con la autorización actual."
            />
          ) : null}

          {view.detail.kind === 'ready' ? (
            <SectionCard title="Detalle autorizado">
              <Text style={styles.status}>
                {caseTypeLabel(view.detail.detail.caseType)}
                {' · '}
                {caseStateLabel(view.detail.detail.state)}
              </Text>
              <Text style={styles.meta}>
                {marketLabel(view.detail.detail.marketCountryCode)}
              </Text>
              <Text style={styles.body}>
                Sujeto: {view.detail.detail.subjectName ?? 'No disponible'}
              </Text>
              {view.detail.detail.equineName ? (
                <Text style={styles.body}>
                  Equino: {view.detail.detail.equineName}
                  {' · '}
                  {relationLabel(view.detail.detail.relationType)}
                  {' · '}
                  {relationLabel(view.detail.detail.relationRole)}
                </Text>
              ) : null}
              {view.detail.detail.evidence.map((item) => (
                <Text
                  key={`${item.category}-${item.documentCountryCode ?? ''}`}
                  style={styles.body}
                >
                  {evidenceCategoryLabel(item.category)}
                  {item.documentCountryCode
                    ? ` · ${marketLabel(item.documentCountryCode)}`
                    : ''}
                </Text>
              ))}
              <Text style={styles.notice}>
                {view.detail.detail.evidenceSufficient
                  ? EVIDENCE_PRESENT_COPY
                  : EVIDENCE_INCOMPLETE_COPY}
              </Text>
              <Text style={styles.notice}>{DECISION_BLOCKED_COPY}</Text>
            </SectionCard>
          ) : null}

          <Pressable
            accessibilityRole="button"
            disabled={view.actionsBlocked}
            onPress={view.refresh}
            style={styles.secondaryButton}
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
    marginTop: 4,
    color: colors.muted,
    fontSize: 14,
  },
  status: {
    color: colors.text,
    fontSize: 16,
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
  message: {
    marginBottom: 12,
    color: colors.text,
    fontSize: 15,
    lineHeight: 22,
  },
  queueRow: {
    paddingVertical: 12,
    borderTopWidth: 1,
    borderTopColor: colors.border,
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
  secondaryButtonText: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
});
