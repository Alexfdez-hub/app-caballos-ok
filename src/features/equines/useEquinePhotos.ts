import { useCallback, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';

import {
  equinePhotoListState,
  finalizeUploadedPhoto,
  refreshEquinePhotoRead,
  retireEquinePhoto,
  uploadEquinePhoto,
} from './equinePhotoFlow';
import type {
  EquinePhotoSummary,
  SelectedEquinePhoto,
  SignedPhotoRead,
} from './equinePhotoFlow';
import { equinePhotoGateway } from './equinePhotoService';

export function useEquinePhotos(equineId: string, enabled: boolean) {
  const [photos, setPhotos] = useState<EquinePhotoSummary[]>([]);
  const [reads, setReads] = useState<Record<string, SignedPhotoRead>>({});
  const [isLoading, setIsLoading] = useState(enabled);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [pendingFinalizeId, setPendingFinalizeId] = useState<string | null>(null);
  const [pendingRetireId, setPendingRetireId] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!enabled) {
      setPhotos([]);
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    setErrorMessage(null);
    const listed = await equinePhotoGateway.list(equineId);
    if ('error' in listed) {
      setErrorMessage('No se pudo completar la foto. Inténtalo de nuevo.');
      setIsLoading(false);
      return;
    }

    const now = Date.now();
    const nextReads: Record<string, SignedPhotoRead> = {};
    for (const photo of listed) {
      const signed = await refreshEquinePhotoRead({
        mediaId: photo.mediaId,
        current: undefined,
        now,
        gateway: equinePhotoGateway,
        force: true,
      });
      if ('signedReadUrl' in signed) {
        nextReads[photo.mediaId] = signed;
      }
    }
    setPhotos(listed);
    setReads(nextReads);
    setIsLoading(false);
  }, [enabled, equineId]);

  useFocusEffect(
    useCallback(() => {
      void refresh();
    }, [refresh]),
  );

  async function addPhoto(photo: SelectedEquinePhoto) {
    setActionMessage(null);
    const result = await uploadEquinePhoto({
      equineId,
      photo,
      isPrimary: !photos.some((item) => item.isPrimary),
      gateway: equinePhotoGateway,
    });
    if (result.status !== 'ready') {
      setActionMessage(result.message);
      setPendingFinalizeId(result.mediaId ?? null);
      return;
    }
    setPendingFinalizeId(null);
    await refresh();
  }

  async function retryFinalize() {
    if (!pendingFinalizeId) {
      return;
    }
    const result = await finalizeUploadedPhoto(pendingFinalizeId, equinePhotoGateway);
    if (result.status !== 'ready') {
      setActionMessage(result.message);
      return;
    }
    setPendingFinalizeId(null);
    setActionMessage(null);
    await refresh();
  }

  async function refreshRead(mediaId: string) {
    const signed = await refreshEquinePhotoRead({
      mediaId,
      current: reads[mediaId],
      now: Date.now(),
      gateway: equinePhotoGateway,
      force: true,
    });
    if ('signedReadUrl' in signed) {
      setReads((current) => ({ ...current, [mediaId]: signed }));
      return;
    }
    setActionMessage(signed.message);
  }

  async function retire(mediaId: string) {
    setPendingRetireId(mediaId);
    const result = await retireEquinePhoto(mediaId, equinePhotoGateway);
    if (result.status !== 'ready') {
      setActionMessage(result.message);
      return;
    }
    setPendingRetireId(null);
    setActionMessage(null);
    await refresh();
  }

  async function retryRetire() {
    if (!pendingRetireId) {
      return;
    }
    await retire(pendingRetireId);
  }

  return {
    photos,
    reads,
    isLoading,
    errorMessage,
    actionMessage,
    pendingFinalizeId,
    pendingRetireId,
    listState: equinePhotoListState({
      isLoading,
      errorMessage,
      count: photos.length,
    }),
    refresh,
    addPhoto,
    retryFinalize,
    refreshRead,
    retire,
    retryRetire,
  };
}
