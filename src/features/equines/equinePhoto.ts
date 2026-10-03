// Stage 034 client. PostgreSQL lists metadata. Edge Functions prepare,
// finalize, sign reads and retire. This module never sends a storage path,
// never reads a bucket, and never builds a public object URL.

export const MAX_EQUINE_PHOTO_BYTES = 8 * 1024 * 1024;
export const SIGNED_READ_TTL_SECONDS = 300;
export const PHOTO_MUTATION_ATTEMPTS = 2;

const ALLOWED_PHOTO_MIMES = ['image/jpeg', 'image/png', 'image/webp'] as const;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PUBLIC_OBJECT_PATH = /\/object\/public\//i;

export type AllowedPhotoMime = (typeof ALLOWED_PHOTO_MIMES)[number];

export type PhotoClientCode =
  | 'unauthorized'
  | 'unavailable'
  | 'invalid_photo'
  | 'retry'
  | 'abandoned';

export class EquinePhotoClientError extends Error {
  readonly code: PhotoClientCode;

  constructor(code: PhotoClientCode) {
    super(code);
    this.name = 'EquinePhotoClientError';
    this.code = code;
  }
}

export type SelectedEquinePhoto = {
  mimeType: AllowedPhotoMime;
  sizeBytes: number;
  bytes: Uint8Array;
};

export type EquinePhotoSummary = {
  mediaId: string;
  sortOrder: number;
  isPrimary: boolean;
  createdAt: string;
};

export type EquinePhotoCard = EquinePhotoSummary & {
  read:
    | { status: 'ready'; signedReadUrl: string; expiresAtMs: number }
    | { status: 'error'; message: string };
};

export type PhotoPanelPhase = 'loading' | 'error' | 'empty' | 'ready';

export type EquinePhotoFunctionName =
  | 'prepare-my-equine-photo'
  | 'finalize-my-equine-photo'
  | 'sign-my-equine-photo-read'
  | 'retire-my-equine-photo';

export type PhotoCallResult = {
  status: number;
  body: Record<string, unknown>;
};

export type EquinePhotoGateway = {
  listPhotos(equineId: string): Promise<unknown>;
  invoke(
    name: EquinePhotoFunctionName,
    body: Record<string, unknown>,
  ): Promise<PhotoCallResult>;
  uploadSigned(
    url: string,
    contentType: AllowedPhotoMime,
    bytes: Uint8Array,
  ): Promise<void>;
};

const MESSAGES: Record<PhotoClientCode | 'generic', string> = {
  unauthorized: 'Inicia sesión para continuar.',
  unavailable: 'Esa foto no está disponible para tu cuenta.',
  invalid_photo: 'Elige una imagen JPEG, PNG o WebP de hasta 8 MB.',
  retry: 'No se pudo completar la foto. Inténtalo de nuevo.',
  abandoned: 'La foto no se guardó. Elige la imagen e inténtalo de nuevo.',
  generic: 'No se pudo completar la foto. Inténtalo de nuevo.',
};

export function userFacingEquinePhotoMessage(error: unknown): string {
  if (error instanceof EquinePhotoClientError) {
    return MESSAGES[error.code];
  }

  const raw = rawMessage(error);
  if (raw.includes('Authentication required') || raw.includes('JWT')) {
    return MESSAGES.unauthorized;
  }
  if (
    raw.includes('Equine photo is not available') ||
    raw.includes('Identity could not be resolved') ||
    raw.includes('Equine is not available')
  ) {
    return MESSAGES.unavailable;
  }
  return MESSAGES.generic;
}

export function derivePhotoPanel(input: {
  isLoading: boolean;
  errorMessage: string | null;
  photoCount: number;
}): PhotoPanelPhase {
  if (input.isLoading) {
    return 'loading';
  }
  if (input.errorMessage) {
    return 'error';
  }
  if (input.photoCount === 0) {
    return 'empty';
  }
  return 'ready';
}

export function visiblePhotoCards<T>(phase: PhotoPanelPhase, photos: T[]): T[] {
  return phase === 'ready' ? photos : [];
}

export function photoPanelAfterListFailure(error: unknown): {
  phase: 'error';
  errorMessage: string;
  photos: [];
} {
  return {
    phase: 'error',
    errorMessage: userFacingEquinePhotoMessage(error),
    photos: [],
  };
}

export function nextPhotoIsPrimary(photos: { isPrimary: boolean }[]): boolean {
  return !photos.some((photo) => photo.isPrimary);
}

export function mediaIdsNeedingRefresh(
  photos: Array<{ mediaId: string; expiresAtMs: number | null }>,
  nowMs: number,
): string[] {
  return photos
    .filter((photo) => photo.expiresAtMs !== null && nowMs >= photo.expiresAtMs)
    .map((photo) => photo.mediaId);
}

export function nextReadRefreshDelayMs(
  expiresAtMs: number[],
  nowMs: number,
): number | null {
  if (expiresAtMs.length === 0) {
    return null;
  }
  return Math.max(0, Math.min(...expiresAtMs) - nowMs);
}

export function selectedPhotoFromParts(input: {
  mimeType: string | null;
  fileName: string | null;
  bytes: Uint8Array;
}): SelectedEquinePhoto {
  const mimeType = normalizePhotoMime(input.mimeType, input.fileName);
  if (
    input.bytes.byteLength < 1 ||
    input.bytes.byteLength > MAX_EQUINE_PHOTO_BYTES
  ) {
    throw new EquinePhotoClientError('invalid_photo');
  }
  return {
    mimeType,
    sizeBytes: input.bytes.byteLength,
    bytes: input.bytes,
  };
}

export function assertPrivateSignedUrl(url: string): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new EquinePhotoClientError('retry');
  }
  if (PUBLIC_OBJECT_PATH.test(parsed.pathname)) {
    throw new EquinePhotoClientError('retry');
  }
  const localHost =
    parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1';
  if (parsed.protocol === 'https:') {
    return;
  }
  if (parsed.protocol === 'http:' && localHost) {
    return;
  }
  throw new EquinePhotoClientError('retry');
}

export function photoResultFromParts(
  status: number,
  body: unknown,
): PhotoCallResult {
  if (!isRecord(body)) {
    return { status, body: { error: 'retry' } };
  }
  return { status, body };
}

export async function photoResultFromInvoke(input: {
  data: unknown;
  error: unknown;
}): Promise<PhotoCallResult> {
  if (!input.error) {
    return photoResultFromParts(200, input.data);
  }

  const context = isRecord(input.error) ? input.error.context : undefined;
  if (isRecord(context) && typeof context.status === 'number') {
    const readJson = context.json;
    if (typeof readJson === 'function') {
      try {
        const parsed = await readJson.call(context);
        return photoResultFromParts(context.status, parsed);
      } catch {
        return { status: context.status, body: { error: 'retry' } };
      }
    }
    return { status: context.status, body: { error: 'retry' } };
  }

  return { status: 503, body: { error: 'retry' } };
}

export async function loadEquinePhotoCards(
  gateway: EquinePhotoGateway,
  equineId: string,
  nowMs: number,
): Promise<EquinePhotoCard[]> {
  if (!isUuid(equineId)) {
    throw new EquinePhotoClientError('invalid_photo');
  }

  let listed: unknown;
  try {
    listed = await gateway.listPhotos(equineId);
  } catch (error) {
    throw asPhotoError(error);
  }

  const rows = parseEquinePhotoList(listed, equineId);
  return Promise.all(
    rows.map(async (row) => {
      try {
        const read = await refreshEquinePhotoRead(gateway, row.mediaId, nowMs);
        return {
          ...row,
          read: {
            status: 'ready' as const,
            signedReadUrl: read.signedReadUrl,
            expiresAtMs: read.expiresAtMs,
          },
        };
      } catch (error) {
        return {
          ...row,
          read: {
            status: 'error' as const,
            message: userFacingEquinePhotoMessage(error),
          },
        };
      }
    }),
  );
}

export async function refreshEquinePhotoRead(
  gateway: EquinePhotoGateway,
  mediaId: string,
  nowMs: number,
): Promise<{ signedReadUrl: string; expiresAtMs: number }> {
  if (!isUuid(mediaId)) {
    throw new EquinePhotoClientError('invalid_photo');
  }
  const result = await gateway.invoke('sign-my-equine-photo-read', { mediaId });
  if (!isSuccess(result)) {
    throw errorFromResult(result);
  }
  return parseSignedRead(result.body, mediaId, nowMs);
}

export async function uploadEquinePhoto(
  gateway: EquinePhotoGateway,
  input: {
    equineId: string;
    isPrimary: boolean;
    photo: SelectedEquinePhoto;
  },
): Promise<{ mediaId: string }> {
  if (!isUuid(input.equineId) || typeof input.isPrimary !== 'boolean') {
    throw new EquinePhotoClientError('invalid_photo');
  }
  assertSelectedPhoto(input.photo);

  const prepared = await gateway.invoke('prepare-my-equine-photo', {
    equineId: input.equineId,
    isPrimary: input.isPrimary,
    contentType: input.photo.mimeType,
  });
  if (!isSuccess(prepared)) {
    throw errorFromResult(prepared);
  }

  const preparedPhoto = parsePrepare(prepared.body, input.equineId);
  try {
    await gateway.uploadSigned(
      preparedPhoto.signedUploadUrl,
      input.photo.mimeType,
      input.photo.bytes,
    );
  } catch (error) {
    if (error instanceof EquinePhotoClientError) {
      throw error;
    }
    throw new EquinePhotoClientError('retry');
  }

  await invokeMutation(gateway, 'finalize-my-equine-photo', {
    mediaId: preparedPhoto.mediaId,
  });
  return { mediaId: preparedPhoto.mediaId };
}

export async function retireEquinePhoto(
  gateway: EquinePhotoGateway,
  mediaId: string,
): Promise<void> {
  if (!isUuid(mediaId)) {
    throw new EquinePhotoClientError('invalid_photo');
  }
  await invokeMutation(gateway, 'retire-my-equine-photo', { mediaId });
}

function assertSelectedPhoto(photo: SelectedEquinePhoto): void {
  if (
    !ALLOWED_PHOTO_MIMES.includes(photo.mimeType) ||
    photo.bytes.byteLength !== photo.sizeBytes ||
    photo.sizeBytes < 1 ||
    photo.sizeBytes > MAX_EQUINE_PHOTO_BYTES
  ) {
    throw new EquinePhotoClientError('invalid_photo');
  }
}

function normalizePhotoMime(
  mimeType: string | null,
  fileName: string | null,
): AllowedPhotoMime {
  const normalized = (mimeType ?? '').trim().toLowerCase();
  const mime = normalized === 'image/jpg' ? 'image/jpeg' : normalized;
  if (mime.length > 0) {
    if (isAllowedMime(mime)) {
      return mime;
    }
    throw new EquinePhotoClientError('invalid_photo');
  }

  const inferred = mimeFromFileName(fileName);
  if (!inferred) {
    throw new EquinePhotoClientError('invalid_photo');
  }
  return inferred;
}

function mimeFromFileName(fileName: string | null): AllowedPhotoMime | null {
  if (!fileName) {
    return null;
  }
  const lower = fileName.toLowerCase().split('?')[0] ?? '';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return null;
}

function parseEquinePhotoList(
  value: unknown,
  equineId: string,
): EquinePhotoSummary[] {
  if (!Array.isArray(value)) {
    throw new EquinePhotoClientError('retry');
  }
  return value.map((row) => parseEquinePhotoRow(row, equineId));
}

function parseEquinePhotoRow(
  value: unknown,
  equineId: string,
): EquinePhotoSummary {
  if (
    !isRecord(value) ||
    !isUuid(value.media_id) ||
    typeof value.storage_path !== 'string' ||
    typeof value.sort_order !== 'number' ||
    !Number.isInteger(value.sort_order) ||
    typeof value.is_primary !== 'boolean' ||
    typeof value.created_at !== 'string' ||
    value.created_at.length === 0
  ) {
    throw new EquinePhotoClientError('retry');
  }
  if (value.storage_path !== `${equineId}/${value.media_id}`) {
    throw new EquinePhotoClientError('retry');
  }

  return {
    mediaId: value.media_id,
    sortOrder: value.sort_order,
    isPrimary: value.is_primary,
    createdAt: value.created_at,
  };
}

function parsePrepare(
  body: Record<string, unknown>,
  equineId: string,
): { mediaId: string; signedUploadUrl: string } {
  const { mediaId, storagePath, signedUploadUrl } = body;
  if (
    !isUuid(mediaId) ||
    typeof storagePath !== 'string' ||
    typeof signedUploadUrl !== 'string' ||
    storagePath !== `${equineId}/${mediaId}`
  ) {
    throw new EquinePhotoClientError('retry');
  }
  assertPrivateSignedUrl(signedUploadUrl);
  return { mediaId, signedUploadUrl };
}

function parseSignedRead(
  body: Record<string, unknown>,
  mediaId: string,
  nowMs: number,
): { signedReadUrl: string; expiresAtMs: number } {
  if (
    body.mediaId !== mediaId ||
    body.expiresIn !== SIGNED_READ_TTL_SECONDS ||
    typeof body.signedReadUrl !== 'string'
  ) {
    throw new EquinePhotoClientError('retry');
  }
  assertPrivateSignedUrl(body.signedReadUrl);
  return {
    signedReadUrl: body.signedReadUrl,
    expiresAtMs: nowMs + SIGNED_READ_TTL_SECONDS * 1000,
  };
}

async function invokeMutation(
  gateway: EquinePhotoGateway,
  name: 'finalize-my-equine-photo' | 'retire-my-equine-photo',
  body: Record<string, unknown>,
): Promise<void> {
  let last: PhotoCallResult | null = null;
  for (let attempt = 0; attempt < PHOTO_MUTATION_ATTEMPTS; attempt += 1) {
    last = await gateway.invoke(name, body);
    if (last.body.abandoned === true) {
      throw new EquinePhotoClientError('abandoned');
    }
    if (isSuccess(last)) {
      return;
    }
    if (last.body.error !== 'retry') {
      throw errorFromResult(last);
    }
  }
  throw errorFromResult(last ?? { status: 503, body: { error: 'retry' } });
}

function isSuccess(result: PhotoCallResult): boolean {
  return (
    result.status >= 200 &&
    result.status < 300 &&
    result.body.error == null &&
    result.body.abandoned !== true
  );
}

function errorFromResult(result: PhotoCallResult): EquinePhotoClientError {
  const code = result.body.error;
  if (
    code === 'unauthorized' ||
    code === 'unavailable' ||
    code === 'invalid_photo' ||
    code === 'retry'
  ) {
    return new EquinePhotoClientError(code);
  }
  if (result.status === 401) {
    return new EquinePhotoClientError('unauthorized');
  }
  if (result.status === 400) {
    return new EquinePhotoClientError('invalid_photo');
  }
  if (result.status === 403 || result.status === 409) {
    return new EquinePhotoClientError('unavailable');
  }
  return new EquinePhotoClientError('retry');
}

function asPhotoError(error: unknown): EquinePhotoClientError {
  if (error instanceof EquinePhotoClientError) {
    return error;
  }
  const message = userFacingEquinePhotoMessage(error);
  if (message === MESSAGES.unauthorized) {
    return new EquinePhotoClientError('unauthorized');
  }
  if (message === MESSAGES.unavailable) {
    return new EquinePhotoClientError('unavailable');
  }
  return new EquinePhotoClientError('retry');
}

function isAllowedMime(value: string): value is AllowedPhotoMime {
  return ALLOWED_PHOTO_MIMES.includes(value as AllowedPhotoMime);
}

function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function rawMessage(error: unknown): string {
  if (isRecord(error) && typeof error.message === 'string') {
    return error.message;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return '';
}
