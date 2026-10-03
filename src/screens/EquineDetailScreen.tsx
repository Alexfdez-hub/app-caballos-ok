import { useState } from 'react';
import {
  ActivityIndicator,
  Image,
  Pressable,
  StyleSheet,
  Text,
} from 'react-native';
import * as ImagePicker from 'expo-image-picker';

import type { EquineDetailScreenProps } from '../app/navigation/types';
import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import { equineTypeLabel } from '../features/equines/labels';
import { useEquineDetail } from '../features/equines/useEquineDetail';
import { useEquinePhotos } from '../features/equines/useEquinePhotos';

export default function EquineDetailScreen({ route }: EquineDetailScreenProps) {
  const equineId = route.params.equineId;
  const { equine, isLoading, errorMessage, refresh } = useEquineDetail(equineId);
  const photos = useEquinePhotos(equineId, equine?.isPrimaryManager === true);
  const [isChoosing, setIsChoosing] = useState(false);

  async function choosePhoto() {
    setIsChoosing(true);
    try {
      const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!permission.granted) {
        return;
      }
      const picked = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'],
        quality: 1,
      });
      if (picked.canceled || !picked.assets[0]) {
        return;
      }
      const asset = picked.assets[0];
      const response = await fetch(asset.uri);
      const bytes = new Uint8Array(await response.arrayBuffer());
      await photos.addPhoto({
        contentType: asset.mimeType ?? '',
        size: bytes.byteLength,
        bytes,
      });
    } finally {
      setIsChoosing(false);
    }
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
          <Text style={styles.hint}>El equino queda privado.</Text>
        </SectionCard>
      ) : null}

      {equine?.isPrimaryManager ? (
        <SectionCard title="Fotos privadas">
          <Pressable
            accessibilityRole="button"
            disabled={isChoosing}
            onPress={() => {
              void choosePhoto();
            }}
            style={({ pressed }) => [
              styles.primaryButton,
              pressed && styles.buttonPressed,
            ]}
          >
            <Text style={styles.primaryButtonText}>
              {isChoosing ? 'Eligiendo foto' : 'Añadir foto'}
            </Text>
          </Pressable>

          {photos.actionMessage ? (
            <Text accessibilityRole="alert" style={styles.message}>
              {photos.actionMessage}
            </Text>
          ) : null}

          {photos.pendingFinalizeId ? (
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                void photos.retryFinalize();
              }}
              style={({ pressed }) => [
                styles.secondaryButton,
                pressed && styles.buttonPressed,
              ]}
            >
              <Text style={styles.secondaryButtonText}>Reintentar confirmación</Text>
            </Pressable>
          ) : null}

          {photos.listState === 'loading' ? (
            <ActivityIndicator color={colors.text} />
          ) : null}

          {photos.listState === 'error' ? (
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

          {photos.listState === 'empty' ? (
            <EmptyStateCard
              title="Sin fotos"
              description="Todavía no hay una foto privada de este equino."
            />
          ) : null}

          {photos.photos.map((photo) => {
            const read = photos.reads[photo.mediaId];
            return (
              <SectionCard key={photo.mediaId}>
                {read ? (
                  <Image
                    accessibilityLabel={
                      photo.isPrimary ? 'Foto principal del equino' : 'Foto del equino'
                    }
                    onError={() => {
                      void photos.refreshRead(photo.mediaId);
                    }}
                    source={{ uri: read.signedReadUrl }}
                    style={styles.photo}
                  />
                ) : (
                  <Text style={styles.hint}>La vista previa no está disponible.</Text>
                )}
                <Pressable
                  accessibilityRole="button"
                  onPress={() => {
                    void photos.retire(photo.mediaId);
                  }}
                  style={({ pressed }) => [
                    styles.secondaryButton,
                    pressed && styles.buttonPressed,
                  ]}
                >
                  <Text style={styles.secondaryButtonText}>Retirar foto</Text>
                </Pressable>
              </SectionCard>
            );
          })}

          {photos.pendingRetireId ? (
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                void photos.retryRetire();
              }}
              style={({ pressed }) => [
                styles.secondaryButton,
                pressed && styles.buttonPressed,
              ]}
            >
              <Text style={styles.secondaryButtonText}>Reintentar retirada</Text>
            </Pressable>
          ) : null}
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
  photo: {
    width: '100%',
    height: 220,
    marginBottom: 12,
    borderRadius: 8,
    backgroundColor: colors.background,
  },
  primaryButton: {
    minHeight: 50,
    marginBottom: 16,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: colors.text,
  },
  primaryButtonText: {
    color: colors.surface,
    fontSize: 16,
    fontWeight: '600',
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
