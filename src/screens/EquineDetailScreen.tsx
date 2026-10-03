import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import type { EquineDetailScreenProps } from '../app/navigation/types';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import { equineTypeLabel } from '../features/equines/labels';
import { useEquineDetail } from '../features/equines/useEquineDetail';

export default function EquineDetailScreen({ route }: EquineDetailScreenProps) {
  const { equine, isLoading, errorMessage, refresh } = useEquineDetail(
    route.params.equineId,
  );

  return (
    <ScreenScaffold>
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

      {equine ? (
        <SectionCard title={equine.equineName}>
          <Text style={styles.line}>{equineTypeLabel(equine.equineType)}</Text>
          <Text style={styles.line}>
            {equine.isOwner ? 'Propiedad al 100 %' : 'Sin propiedad en tu cuenta'}
          </Text>
          <Text style={styles.line}>
            {equine.isPrimaryManager
              ? 'Gestor principal'
              : 'Sin gestión principal vigente'}
          </Text>
          <Text style={styles.hint}>
            El equino queda privado. Las fotos no se suben desde esta pantalla.
          </Text>
        </SectionCard>
      ) : null}
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
  line: {
    marginBottom: 8,
    color: colors.text,
    fontSize: 15,
  },
  hint: {
    marginTop: 8,
    color: colors.muted,
    fontSize: 13,
    lineHeight: 18,
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
  secondaryButtonText: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
});
