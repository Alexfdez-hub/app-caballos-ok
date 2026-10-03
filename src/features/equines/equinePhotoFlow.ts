export const PHOTO_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
export const MAX_PHOTO_BYTES = 8 * 1024 * 1024;
export const SIGNED_READ_TTL_SECONDS = 300;

export type SelectedEquinePhoto = {
  contentType: string;
  size: number;
  bytes: Uint8Array;
};

export type EquinePhotoSummary = {
  mediaId: string;
  storagePath: string;
  isPrimary: boolean;
};

export type SignedPhotoRead = {
  mediaId: string;
  signedReadUrl: string;
  expiresIn: number;
  signedAt: number;
};

export type PhotoFlowFailure = {
  status: 'invalid' | 'unavailable' | 'retry';
  message: string;
  mediaId?: string;
};

export type PhotoGateway = {
  prepare(input: {
    equineId: string;
    isPrimary: boolean;
    contentType: string;
  }): Promise<
    | { mediaId: string; storagePath: string; signedUploadUrl: string }
    | { error: string; mediaId?: string }
  >;
  upload(input: {
    signedUploadUrl: string;
    bytes: Uint8Array;
    contentType: string;
  }): Promise<{ ok: true } | { error: string }>;
  finalize(mediaId: string): Promise<{ ok: true } | { error: string }>;
  signRead(mediaId: string): Promise<
    | { signedReadUrl: string; expiresIn: number }
    | { error: string }
  >;
  retire(mediaId: string): Promise<{ ok: true } | { error: string }>;
  list(equineId: string): Promise<EquinePhotoSummary[] | { error: string }>;
};

const INVALID_TYPE = 'Elige una foto JPEG, PNG o WebP.';
const INVALID_SIZE = 'La foto no puede superar 8 MB.';
const UNAVAILABLE = 'Esa foto no está disponible para tu cuenta.';
const RETRY = 'No se pudo completar la foto. Inténtalo de nuevo.';
const AUTH = 'Inicia sesión para continuar.';

export function equinePhotoListState(input: {
  isLoading: boolean;
  errorMessage: string | null;
  count: number;
}): 'loading' | 'error' | 'empty' | 'ready' {
  if (input.isLoading) {
    return 'loading';
  }
  if (input.errorMessage) {
    return 'error';
  }
  if (input.count === 0) {
    return 'empty';
  }
  return 'ready';
}

export function validateSelectedPhoto(
  photo: SelectedEquinePhoto,
): PhotoFlowFailure | null {
  if (
    !PHOTO_CONTENT_TYPES.includes(
      photo.contentType as (typeof PHOTO_CONTENT_TYPES)[number],
    )
  ) {
    return { status: 'invalid', message: INVALID_TYPE };
  }
  if (!Number.isFinite(photo.size) || photo.size <= 0 || photo.size > MAX_PHOTO_BYTES) {
    return { status: 'invalid', message: INVALID_SIZE };
  }
  if (photo.bytes.byteLength !== photo.size) {
    return { status: 'invalid', message: INVALID_SIZE };
  }
  return null;
}

export function userFacingEquinePhotoMessage(error: unknown): string {
  const message =
    error && typeof error === 'object' && 'message' in error
      ? String((error as { message?: unknown }).message ?? '')
      : error instanceof Error
        ? error.message
        : typeof error === 'string'
          ? error
          : '';

  if (
    message === 'unauthorized' ||
    message.includes('Authentication required') ||
    message.includes('JWT')
  ) {
    return AUTH;
  }
  if (message === 'invalid_photo') {
    return INVALID_TYPE;
  }
  if (message === 'unavailable' || message.includes('Equine photo is not available')) {
    return UNAVAILABLE;
  }
  return RETRY;
}

export function readUrlNeedsRefresh(
  read: SignedPhotoRead | undefined,
  now: number,
): boolean {
  if (!read) {
    return true;
  }
  return now >= read.signedAt + read.expiresIn * 1000;
}

export async function uploadEquinePhoto(input: {
  equineId: string;
  photo: SelectedEquinePhoto;
  isPrimary: boolean;
  gateway: PhotoGateway;
}): Promise<{ status: 'ready'; mediaId: string } | PhotoFlowFailure> {
  const invalid = validateSelectedPhoto(input.photo);
  if (invalid) {
    return invalid;
  }

  const prepared = await input.gateway.prepare({
    equineId: input.equineId,
    isPrimary: input.isPrimary,
    contentType: input.photo.contentType,
  });
  if ('error' in prepared) {
    return reconcileUnfinishedPrepare(prepared, input.gateway);
  }
  if (!prepared.storagePath.startsWith(`${input.equineId}/`)) {
    return { status: 'retry', message: RETRY };
  }

  const uploaded = await input.gateway.upload({
    signedUploadUrl: prepared.signedUploadUrl,
    bytes: input.photo.bytes,
    contentType: input.photo.contentType,
  });
  if ('error' in uploaded) {
    await input.gateway.finalize(prepared.mediaId);
    return { status: 'retry', message: RETRY, mediaId: prepared.mediaId };
  }

  return finalizeUploadedPhoto(prepared.mediaId, input.gateway);
}

export async function finalizeUploadedPhoto(
  mediaId: string,
  gateway: PhotoGateway,
): Promise<{ status: 'ready'; mediaId: string } | PhotoFlowFailure> {
  const finalized = await gateway.finalize(mediaId);
  if ('error' in finalized) {
    const failure = failureFromCode(finalized.error);
    return failure.status === 'retry' ? { ...failure, mediaId } : failure;
  }
  return { status: 'ready', mediaId };
}

export async function refreshEquinePhotoRead(input: {
  mediaId: string;
  current: SignedPhotoRead | undefined;
  now: number;
  gateway: PhotoGateway;
  force?: boolean;
}): Promise<SignedPhotoRead | PhotoFlowFailure> {
  if (!input.force && !readUrlNeedsRefresh(input.current, input.now)) {
    return input.current as SignedPhotoRead;
  }
  const signed = await input.gateway.signRead(input.mediaId);
  if ('error' in signed) {
    return failureFromCode(signed.error);
  }
  if (signed.expiresIn !== SIGNED_READ_TTL_SECONDS) {
    return { status: 'retry', message: RETRY };
  }
  return {
    mediaId: input.mediaId,
    signedReadUrl: signed.signedReadUrl,
    expiresIn: signed.expiresIn,
    signedAt: input.now,
  };
}

export async function retireEquinePhoto(
  mediaId: string,
  gateway: PhotoGateway,
): Promise<{ status: 'ready' } | PhotoFlowFailure> {
  const retired = await gateway.retire(mediaId);
  if ('error' in retired) {
    const failure = failureFromCode(retired.error);
    return failure.status === 'retry' ? { ...failure, mediaId } : failure;
  }
  return { status: 'ready' };
}

async function reconcileUnfinishedPrepare(
  prepared: { error: string; mediaId?: string },
  gateway: PhotoGateway,
): Promise<PhotoFlowFailure> {
  if (!prepared.mediaId) {
    return failureFromCode(prepared.error);
  }
  const reconciled = await gateway.finalize(prepared.mediaId);
  if ('error' in reconciled) {
    const failure = failureFromCode(reconciled.error);
    return failure.status === 'retry' ? { ...failure, mediaId: prepared.mediaId } : failure;
  }
  return { status: 'retry', message: RETRY };
}

export function photoInvokeFailure(
  body: unknown,
): { code: string; mediaId?: string } | null {
  if (!body || typeof body !== 'object' || !('error' in body)) {
    return null;
  }
  const code = (body as { error?: unknown }).error;
  const mediaId = (body as { mediaId?: unknown }).mediaId;
  return {
    code: typeof code === 'string' ? code : 'retry',
    ...(typeof mediaId === 'string' ? { mediaId } : {}),
  };
}

function failureFromCode(code: string): PhotoFlowFailure {
  const message = userFacingEquinePhotoMessage(code);
  if (code === 'invalid_photo') {
    return { status: 'invalid', message };
  }
  if (code === 'unavailable' || code === 'unauthorized') {
    return { status: 'unavailable', message };
  }
  return { status: 'retry', message };
}
