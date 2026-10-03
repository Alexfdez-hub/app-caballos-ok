import { useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Pressable,
  StyleSheet,
  Text,
} from 'react-native';

import type { EquineDetailScreenProps } from '../app/navigation/types';
import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import { equineTypeLabel } from '../features/equines/labels';
import {
  derivePhotoPanel,
  visiblePhotoCards,
} from '../features/equines/equinePhoto';
import type { EquinePhotoCard } from '../features/equines/equinePhoto';
import { selectEquinePhoto } from '../features/equines/selectEquinePhoto';
import { useEquineDetail } from '../features/equines/useEquineDetail';
import { useEquinePhotos } from '../features/equines/useEquinePhotos';

export default function EquineDetailScreen({ route }: EquineDetailScreenProps) {
  const { equine, isLoading, errorMessage, refresh } = useEquineDetail(
    route.params.equineId,
  );
  const photos = useEquinePhotos(route.params.equineId, equine !== null);
  const [isChoosingPhoto, setIsChoosingPhoto] = useState(false);
  const phase = derivePhotoPanel({
    isLoading: photos.isLoading,
    errorMessage: photos.errorMessage,
    photoCount: photos.photos.length,
  });
  const visiblePhotos = visiblePhotoCards(phase, photos.photos);
  const canEditPhotos =
    Boolean(equine?.isPrimaryManager) &&
    (phase === 'ready' || phase === 'empty') &&
    !photos.isMutating &&
    !isChoosingPhoto;
  const showAddPhoto =
    Boolean(equine?.isPrimaryManager) &&
    (phase === 'ready' || phase === 'empty');

  async function handleAddPhoto() {
    setIsChoosingPhoto(true);
    try {
      const selected = await selectEquinePhoto();
      if (!selected) {
        return;
      }
      await photos.uploadPhoto(selected);
    } catch (error) {
      photos.reportActionError(error);
    } finally {
      setIsChoosingPhoto(false);
    }
  }

  function handleRetire(photo: EquinePhotoCard) {
    Alert.alert('Retirar foto', 'La foto dejará de verse en este equino.', [
      { text: 'Cancelar', style: 'cancel' },
      {
        text: 'Retirar',
        style: 'destructive',
        onPress: () => {
          void photos.retirePhoto(photo.mediaId);
        },
      },
    ]);
  }

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
            El equino queda privado. Las fotos se leen con un enlace firmado que caduca.
          </Text>
        </SectionCard>
      ) : null}

      {equine ? (
        <SectionCard title="Fotos">
          {phase === 'loading' ? <ActivityIndicator color={colors.text} /> : null}

          {phase === 'error' && photos.errorMessage ? (
            <>
              <Text accessibilityRole="alert" style={styles.message}>
                {photos.errorMessage}
              </Text>
              <Pressable
                accessibilityRole="button"
                onPress={() => {
                  void photos.refresh();
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

          {phase === 'empty' ? (
            <EmptyStateCard
              title="Sin fotos"
              description="Todavía no hay una foto vigente de este equino."
            />
          ) : null}

          {visiblePhotos.map((photo) => (
            <PhotoCard
              key={photo.mediaId}
              canRetire={canEditPhotos}
              photo={photo}
              onRefresh={() => {
                void photos.refreshRead(photo.mediaId);
              }}
              onRetire={() => handleRetire(photo)}
            />
          ))}

          {photos.actionMessage ? (
            <Text accessibilityRole="alert" style={styles.message}>
              {photos.actionMessage}
            </Text>
          ) : null}

          {showAddPhoto ? (
            <Pressable
              accessibilityRole="button"
              disabled={!canEditPhotos}
              onPress={() => {
                void handleAddPhoto();
              }}
              style={({ pressed }) => [
                styles.primaryButton,
                pressed && styles.buttonPressed,
              ]}
            >
              {photos.isMutating || isChoosingPhoto ? (
                <ActivityIndicator color={colors.surface} />
              ) : (
                <Text style={styles.primaryButtonText}>Añadir foto</Text>
              )}
            </Pressable>
          ) : null}
        </SectionCard>
      ) : null}
    </ScreenScaffold>
  );
}

function PhotoCard({
  photo,
  canRetire,
  onRefresh,
  onRetire,
}: {
  photo: EquinePhotoCard;
  canRetire: boolean;
  onRefresh: () => void;
  onRetire: () => void;
}) {
  const automaticRefreshes = useRef(0);

  return (
    <>
      {photo.isPrimary ? <Text style={styles.primaryLabel}>Principal</Text> : null}
      {photo.read.status === 'ready' ? (
        <Image
          accessibilityLabel={
            photo.isPrimary ? 'Foto principal del equino' : 'Foto del equino'
          }
          onError={() => {
            if (automaticRefreshes.current >= 2) {
              return;
            }
            automaticRefreshes.current += 1;
            onRefresh();
          }}
          source={{ uri: photo.read.signedReadUrl }}
          style={styles.photo}
        />
      ) : (
        <>
          <Text accessibilityRole="alert" style={styles.message}>
            {photo.read.message}
          </Text>
          <Pressable
            accessibilityRole="button"
            onPress={onRefresh}
            style={({ pressed }) => [
              styles.secondaryButton,
              pressed && styles.buttonPressed,
            ]}
          >
            <Text style={styles.secondaryButtonText}>Actualizar foto</Text>
          </Pressable>
        </>
      )}
      {canRetire ? (
        <Pressable
          accessibilityRole="button"
          onPress={onRetire}
          style={({ pressed }) => [
            styles.secondaryButton,
            pressed && styles.buttonPressed,
          ]}
        >
          <Text style={styles.secondaryButtonText}>Retirar foto</Text>
        </Pressable>
      ) : null}
    </>
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
  primaryLabel: {
    marginBottom: 8,
    color: colors.text,
    fontSize: 13,
    fontWeight: '700',
  },
  photo: {
    width: '100%',
    height: 220,
    marginBottom: 12,
    borderRadius: 8,
    backgroundColor: colors.background,
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
  primaryButton: {
    minHeight: 50,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: colors.text,
  },
  buttonPressed: {
    opacity: 0.8,
  },
  secondaryButtonText: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
  primaryButtonText: {
    color: colors.surface,
    fontSize: 16,
    fontWeight: '600',
  },
});
