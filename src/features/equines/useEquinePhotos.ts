import { useCallback, useEffect, useRef, useState } from 'react';

import { createEquinePhotoGateway } from './equinePhotoService';
import {
  loadEquinePhotoCards,
  mediaIdsNeedingRefresh,
  nextPhotoIsPrimary,
  nextReadRefreshDelayMs,
  refreshEquinePhotoRead,
  retireEquinePhoto,
  uploadEquinePhoto,
  userFacingEquinePhotoMessage,
} from './equinePhoto';
import type { EquinePhotoCard, EquinePhotoGateway, SelectedEquinePhoto } from './equinePhoto';

export function useEquinePhotos(equineId: string, enabled: boolean) {
  const gatewayRef = useRef<EquinePhotoGateway | null>(null);
  if (!gatewayRef.current) {
    gatewayRef.current = createEquinePhotoGateway();
  }

  const [photos, setPhotos] = useState<EquinePhotoCard[]>([]);
  const [isLoading, setIsLoading] = useState(enabled);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [isMutating, setIsMutating] = useState(false);
  const requestSeqRef = useRef(0);
  const readsInFlightRef = useRef(new Set<string>());

  const refresh = useCallback(async () => {
    const requestSeq = requestSeqRef.current + 1;
    requestSeqRef.current = requestSeq;
    if (!enabled) {
      setPhotos([]);
      setErrorMessage(null);
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    setErrorMessage(null);
    try {
      const cards = await loadEquinePhotoCards(
        gatewayRef.current as EquinePhotoGateway,
        equineId,
        Date.now(),
      );
      if (requestSeqRef.current !== requestSeq) {
        return;
      }
      setPhotos(cards);
    } catch (error) {
      if (requestSeqRef.current !== requestSeq) {
        return;
      }
      setPhotos([]);
      setErrorMessage(userFacingEquinePhotoMessage(error));
    } finally {
      if (requestSeqRef.current === requestSeq) {
        setIsLoading(false);
      }
    }
  }, [enabled, equineId]);

  const refreshExpired = useCallback(async () => {
    const gateway = gatewayRef.current as EquinePhotoGateway;
    const nowMs = Date.now();
    const expired = mediaIdsNeedingRefresh(
      photos.map((photo) => ({
        mediaId: photo.mediaId,
        expiresAtMs: photo.read.status === 'ready' ? photo.read.expiresAtMs : null,
      })),
      nowMs,
    );
    if (expired.length === 0) {
      return;
    }

    const replacements = new Map<string, EquinePhotoCard['read']>();
    await Promise.all(
      expired.map(async (mediaId) => {
        try {
          const read = await refreshEquinePhotoRead(gateway, mediaId, Date.now());
          replacements.set(mediaId, {
            status: 'ready',
            signedReadUrl: read.signedReadUrl,
            expiresAtMs: read.expiresAtMs,
          });
        } catch (error) {
          replacements.set(mediaId, {
            status: 'error',
            message: userFacingEquinePhotoMessage(error),
          });
        }
      }),
    );

    setPhotos((current) =>
      current.map((photo) => {
        const read = replacements.get(photo.mediaId);
        return read ? { ...photo, read } : photo;
      }),
    );
  }, [photos]);

  const refreshRead = useCallback(async (mediaId: string) => {
    if (readsInFlightRef.current.has(mediaId)) {
      return;
    }
    readsInFlightRef.current.add(mediaId);
    const gateway = gatewayRef.current as EquinePhotoGateway;
    try {
      const read = await refreshEquinePhotoRead(gateway, mediaId, Date.now());
      setPhotos((current) =>
        current.map((photo) =>
          photo.mediaId === mediaId
            ? {
                ...photo,
                read: {
                  status: 'ready',
                  signedReadUrl: read.signedReadUrl,
                  expiresAtMs: read.expiresAtMs,
                },
              }
            : photo,
        ),
      );
    } catch (error) {
      const message = userFacingEquinePhotoMessage(error);
      setPhotos((current) =>
        current.map((photo) =>
          photo.mediaId === mediaId
            ? { ...photo, read: { status: 'error', message } }
            : photo,
        ),
      );
    } finally {
      readsInFlightRef.current.delete(mediaId);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    const delay = nextReadRefreshDelayMs(
      photos.flatMap((photo) =>
        photo.read.status === 'ready' ? [photo.read.expiresAtMs] : [],
      ),
      Date.now(),
    );
    if (delay === null) {
      return undefined;
    }
    const timer = setTimeout(() => {
      void refreshExpired();
    }, delay);
    return () => clearTimeout(timer);
  }, [photos, refreshExpired]);

  const uploadPhoto = useCallback(
    async (photo: SelectedEquinePhoto) => {
      setIsMutating(true);
      setActionMessage(null);
      try {
        await uploadEquinePhoto(gatewayRef.current as EquinePhotoGateway, {
          equineId,
          isPrimary: nextPhotoIsPrimary(photos),
          photo,
        });
        await refresh();
      } catch (error) {
        setActionMessage(userFacingEquinePhotoMessage(error));
      } finally {
        setIsMutating(false);
      }
    },
    [equineId, photos, refresh],
  );

  const retirePhoto = useCallback(
    async (mediaId: string) => {
      setIsMutating(true);
      setActionMessage(null);
      try {
        await retireEquinePhoto(gatewayRef.current as EquinePhotoGateway, mediaId);
        await refresh();
      } catch (error) {
        setActionMessage(userFacingEquinePhotoMessage(error));
      } finally {
        setIsMutating(false);
      }
    },
    [refresh],
  );

  const reportActionError = useCallback((error: unknown) => {
    setActionMessage(userFacingEquinePhotoMessage(error));
  }, []);

  return {
    photos,
    isLoading,
    errorMessage,
    actionMessage,
    isMutating,
    refresh,
    refreshRead,
    uploadPhoto,
    retirePhoto,
    reportActionError,
  };
}
