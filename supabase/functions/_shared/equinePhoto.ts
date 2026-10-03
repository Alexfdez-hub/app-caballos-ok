// Stage 033. PostgreSQL authorizes. This module signs, inspects and
// deletes only the canonical path SQL returned. It never reads a path
// or a person, account or auth-user id from the request body, and it
// never logs tokens, signed URLs or secrets.
//
// Prepare:
// - the caller JWT is validated, then authorize_my_equine_photo_prepare
//   inserts metadata
// - sign an upload URL for that path
// - if signing fails, abandon that new row through the server-only client
// - if that cleanup fails, return retry with mediaId. Finalize then
//   reconciles an absent object by abandoning the same row
//
// Finalize and retire call post-storage metadata mutations only through
// the server-only client, and only after user-scoped authorization and
// the Storage result. The mutation actor is the Auth user id from that
// validated JWT. The user client cannot call those mutations.
//
// Finalize:
// - present and valid, then record_my_equine_photo_finalized: row stays
// - absent, then abandon_my_equine_photo: row is removed
// - storage error: do not abandon or retire; the client retries
// - present but record fails: leave the object; the client retries
// - absent but abandon fails: leave the row; the client retries
// - present but not JPEG, PNG or WebP, or larger than 8 MiB: delete the
//   object, then abandon. A delete error does not abandon.
//
// Retire:
// - delete succeeds or the object is already absent, then
//   retire_my_equine_photo_metadata
// - delete error: do not retire metadata
// - delete succeeded but metadata fails: the client retries; a missing
//   object counts as already deleted
//
// Read URLs last 300 seconds. Upload URLs use Storage platform validity.
// An already issued URL stays valid until it expires.

export const EQUINE_MEDIA_BUCKET = 'equine-media';
export const SIGNED_READ_TTL_SECONDS = 300;
export const MAX_PHOTO_BYTES = 8 * 1024 * 1024;
export const PHOTO_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type PhotoErrorCode = 'unauthorized' | 'unavailable' | 'invalid_photo' | 'retry';

export type RpcResult = {
  data: unknown;
  errorMessage: string | null;
};

export type MetadataMutation =
  | 'abandon_my_equine_photo'
  | 'record_my_equine_photo_finalized'
  | 'retire_my_equine_photo_metadata';

export type UserPhotoClient = {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>;
  authenticatedUserId(): Promise<string | null>;
};

export type InspectedObject =
  | { state: 'present'; contentType: string | null; size: number | null }
  | { state: 'absent' }
  | { state: 'error' };

export type ServerPhotoClient = {
  signUpload(path: string): Promise<{ signedUrl: string } | { error: true }>;
  signRead(path: string, expiresIn: number): Promise<{ signedUrl: string } | { error: true }>;
  inspect(path: string): Promise<InspectedObject>;
  deleteObject(path: string): Promise<'deleted' | 'absent' | 'error'>;
  mutateMetadata(
    name: MetadataMutation,
    mediaId: string,
    authUserId: string,
  ): Promise<RpcResult>;
};

export type PhotoDeps = {
  createUserClient(jwt: string): UserPhotoClient;
  createServerClient(): ServerPhotoClient;
};

export type PhotoResponse = {
  status: number;
  body: Record<string, unknown>;
};

type StorageError = { message?: string; statusCode?: string | number; status?: number } | null;

export type StructuralStorage = {
  createSignedUploadUrl(path: string): Promise<{
    data: { signedUrl?: string } | null;
    error: StorageError;
  }>;
  createSignedUrl(path: string, expiresIn: number): Promise<{
    data: { signedUrl?: string } | null;
    error: StorageError;
  }>;
  info(path: string): Promise<{
    data: { size?: number; contentType?: string | null } | null;
    error: StorageError;
  }>;
  remove(paths: string[]): Promise<{ data: unknown; error: StorageError }>;
};

export function userClientOptions(jwt: string) {
  return {
    global: {
      headers: {
        Authorization: `Bearer ${jwt}`,
      },
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  };
}

export function serverClientOptions() {
  return {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  };
}

export function adaptServerClient(
  storage: StructuralStorage,
): Omit<ServerPhotoClient, 'mutateMetadata'> {
  return {
    async signUpload(path) {
      const signed = await storage.createSignedUploadUrl(path);
      if (signed.error || !signed.data?.signedUrl) {
        return { error: true };
      }
      return { signedUrl: signed.data.signedUrl };
    },
    async signRead(path, expiresIn) {
      const signed = await storage.createSignedUrl(path, expiresIn);
      if (signed.error || !signed.data?.signedUrl) {
        return { error: true };
      }
      return { signedUrl: signed.data.signedUrl };
    },
    async inspect(path) {
      const inspected = await storage.info(path);
      if (inspected.error) {
        return isMissing(inspected.error) ? { state: 'absent' } : { state: 'error' };
      }
      if (!inspected.data) {
        return { state: 'absent' };
      }
      return {
        state: 'present',
        contentType: inspected.data.contentType ?? null,
        size: typeof inspected.data.size === 'number' ? inspected.data.size : null,
      };
    },
    async deleteObject(path) {
      const removed = await storage.remove([path]);
      if (!removed.error) {
        return 'deleted';
      }
      return isMissing(removed.error) ? 'absent' : 'error';
    },
  };
}

export async function handleEquinePhoto(
  action: 'prepare' | 'finalize' | 'read' | 'retire',
  request: Request,
  deps: PhotoDeps,
): Promise<PhotoResponse> {
  const jwt = bearerToken(request);
  if (!jwt) {
    return errorResponse(401, 'unauthorized');
  }

  let body: Record<string, unknown>;
  try {
    const parsed = await request.json();
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return errorResponse(400, 'invalid_photo');
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return errorResponse(400, 'invalid_photo');
  }

  if (hasClientPath(body) || hasClientIdentity(body)) {
    return errorResponse(400, 'invalid_photo');
  }

  const user = deps.createUserClient(jwt);

  if (action === 'prepare') {
    return preparePhoto(body, user, deps);
  }
  if (action === 'finalize') {
    return finalizePhoto(body, user, deps);
  }
  if (action === 'read') {
    return readPhoto(body, user, deps);
  }
  return retirePhoto(body, user, deps);
}

async function preparePhoto(
  body: Record<string, unknown>,
  user: UserPhotoClient,
  deps: PhotoDeps,
): Promise<PhotoResponse> {
  if (!isUuid(body.equineId) || typeof body.isPrimary !== 'boolean') {
    return errorResponse(400, 'invalid_photo');
  }
  if (!isAllowedContentType(body.contentType)) {
    return errorResponse(400, 'invalid_photo');
  }

  const authUserId = await user.authenticatedUserId();
  if (!authUserId) {
    return errorResponse(401, 'unauthorized');
  }

  const authorized = await user.rpc('authorize_my_equine_photo_prepare', {
    p_equine_id: body.equineId,
    p_is_primary: body.isPrimary,
  });
  const pathError = rpcError(authorized.errorMessage);
  if (pathError) {
    return pathError;
  }

  const prepared = firstRow(authorized.data);
  const mediaId = stringField(prepared, 'media_id');
  const storagePath = stringField(prepared, 'storage_path');
  if (!isUuid(mediaId) || storagePath !== `${body.equineId}/${mediaId}`) {
    return errorResponse(503, 'retry');
  }

  const server = deps.createServerClient();
  const signed = await server.signUpload(storagePath);
  if ('error' in signed) {
    return compensateFailedUpload(server, mediaId, authUserId);
  }

  return {
    status: 200,
    body: {
      mediaId,
      storagePath,
      signedUploadUrl: signed.signedUrl,
    },
  };
}

async function finalizePhoto(
  body: Record<string, unknown>,
  user: UserPhotoClient,
  deps: PhotoDeps,
): Promise<PhotoResponse> {
  if (!isUuid(body.mediaId)) {
    return errorResponse(400, 'invalid_photo');
  }

  const authUserId = await user.authenticatedUserId();
  if (!authUserId) {
    return errorResponse(401, 'unauthorized');
  }

  const authorized = await user.rpc('authorize_my_equine_photo_finalize', {
    p_media_id: body.mediaId,
  });
  const pathError = rpcError(authorized.errorMessage);
  if (pathError) {
    return pathError;
  }

  const storagePath = textResult(authorized.data);
  if (!storagePath || !storagePath.endsWith(`/${body.mediaId}`)) {
    return errorResponse(503, 'retry');
  }

  const server = deps.createServerClient();
  const inspected = await server.inspect(storagePath);
  if (inspected.state === 'error') {
    return errorResponse(503, 'retry');
  }

  if (inspected.state === 'absent') {
    return abandonPhoto(server, body.mediaId, authUserId);
  }

  if (!photoIsAcceptable(inspected)) {
    const removed = await server.deleteObject(storagePath);
    if (removed === 'error') {
      return errorResponse(503, 'retry');
    }
    return abandonPhoto(server, body.mediaId, authUserId);
  }

  const recorded = await server.mutateMetadata(
    'record_my_equine_photo_finalized',
    body.mediaId,
    authUserId,
  );
  const recordedError = rpcError(recorded.errorMessage);
  if (recordedError) {
    return recordedError.status === 403
      ? recordedError
      : errorResponse(503, 'retry');
  }

  return { status: 200, body: { mediaId: body.mediaId } };
}

async function readPhoto(
  body: Record<string, unknown>,
  user: UserPhotoClient,
  deps: PhotoDeps,
): Promise<PhotoResponse> {
  if (!isUuid(body.mediaId)) {
    return errorResponse(400, 'invalid_photo');
  }

  const authorized = await user.rpc('authorize_my_equine_photo_read', {
    p_media_id: body.mediaId,
  });
  const pathError = rpcError(authorized.errorMessage);
  if (pathError) {
    return pathError;
  }

  const storagePath = textResult(authorized.data);
  if (!storagePath || !storagePath.endsWith(`/${body.mediaId}`)) {
    return errorResponse(503, 'retry');
  }

  const server = deps.createServerClient();
  const inspected = await server.inspect(storagePath);
  if (inspected.state !== 'present' || !photoIsAcceptable(inspected)) {
    return errorResponse(409, 'unavailable');
  }

  const signed = await server.signRead(storagePath, SIGNED_READ_TTL_SECONDS);
  if ('error' in signed) {
    return errorResponse(503, 'retry');
  }

  return {
    status: 200,
    body: {
      mediaId: body.mediaId,
      signedReadUrl: signed.signedUrl,
      expiresIn: SIGNED_READ_TTL_SECONDS,
    },
  };
}

async function retirePhoto(
  body: Record<string, unknown>,
  user: UserPhotoClient,
  deps: PhotoDeps,
): Promise<PhotoResponse> {
  if (!isUuid(body.mediaId)) {
    return errorResponse(400, 'invalid_photo');
  }

  const authUserId = await user.authenticatedUserId();
  if (!authUserId) {
    return errorResponse(401, 'unauthorized');
  }

  const authorized = await user.rpc('authorize_my_equine_photo_retire', {
    p_media_id: body.mediaId,
  });
  const pathError = rpcError(authorized.errorMessage);
  if (pathError) {
    return pathError;
  }

  const storagePath = textResult(authorized.data);
  if (!storagePath || !storagePath.endsWith(`/${body.mediaId}`)) {
    return errorResponse(503, 'retry');
  }

  const server = deps.createServerClient();
  const removed = await server.deleteObject(storagePath);
  if (removed === 'error') {
    return errorResponse(503, 'retry');
  }

  const retired = await server.mutateMetadata(
    'retire_my_equine_photo_metadata',
    body.mediaId,
    authUserId,
  );
  const retiredError = rpcError(retired.errorMessage);
  if (retiredError) {
    return retiredError.status === 403
      ? retiredError
      : errorResponse(503, 'retry');
  }

  return { status: 200, body: { mediaId: body.mediaId } };
}

async function compensateFailedUpload(
  server: ServerPhotoClient,
  mediaId: string,
  authUserId: string,
): Promise<PhotoResponse> {
  const abandoned = await server.mutateMetadata(
    'abandon_my_equine_photo',
    mediaId,
    authUserId,
  );
  if (abandoned.errorMessage) {
    return { status: 503, body: { error: 'retry', mediaId } };
  }
  return errorResponse(503, 'retry');
}

async function abandonPhoto(
  server: ServerPhotoClient,
  mediaId: string,
  authUserId: string,
): Promise<PhotoResponse> {
  const abandoned = await server.mutateMetadata(
    'abandon_my_equine_photo',
    mediaId,
    authUserId,
  );
  const abandonedError = rpcError(abandoned.errorMessage);
  if (abandonedError) {
    return abandonedError.status === 403
      ? abandonedError
      : errorResponse(503, 'retry');
  }
  return { status: 200, body: { mediaId, abandoned: true } };
}

function photoIsAcceptable(
  inspected: Extract<InspectedObject, { state: 'present' }>,
): boolean {
  return (
    isAllowedContentType(inspected.contentType) &&
    typeof inspected.size === 'number' &&
    inspected.size > 0 &&
    inspected.size <= MAX_PHOTO_BYTES
  );
}

function isAllowedContentType(value: unknown): value is (typeof PHOTO_CONTENT_TYPES)[number] {
  return (
    typeof value === 'string' &&
    PHOTO_CONTENT_TYPES.includes(value as (typeof PHOTO_CONTENT_TYPES)[number])
  );
}

function bearerToken(request: Request): string | null {
  const header = request.headers.get('Authorization') ?? request.headers.get('authorization');
  if (!header) {
    return null;
  }
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  if (!match || match[1].length < 20) {
    return null;
  }
  return match[1];
}

function hasClientPath(body: Record<string, unknown>): boolean {
  return ['path', 'storagePath', 'storage_path', 'objectPath', 'object_path'].some(
    (key) => key in body,
  );
}

function hasClientIdentity(body: Record<string, unknown>): boolean {
  return [
    'personId',
    'person_id',
    'accountId',
    'account_id',
    'authUserId',
    'auth_user_id',
    'ownerId',
    'owner_id',
    'managerId',
    'manager_id',
    'userId',
    'user_id',
  ].some((key) => key in body);
}

function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== 'object') {
    return null;
  }
  return row as Record<string, unknown>;
}

function stringField(row: Record<string, unknown> | null, key: string): string | null {
  const value = row?.[key];
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function textResult(data: unknown): string | null {
  if (typeof data === 'string' && data.length > 0) {
    return data;
  }
  return stringField(firstRow(data), 'storage_path');
}

function rpcError(message: string | null): PhotoResponse | null {
  if (!message) {
    return null;
  }
  if (message.includes('Authentication required') || message.includes('JWT')) {
    return errorResponse(401, 'unauthorized');
  }
  if (
    message.includes('Equine photo is not available') ||
    message.includes('Identity could not be resolved') ||
    message.includes('Equine creation is not available')
  ) {
    return errorResponse(403, 'unavailable');
  }
  return errorResponse(503, 'retry');
}

function errorResponse(status: number, error: PhotoErrorCode): PhotoResponse {
  return { status, body: { error } };
}

function isMissing(error: StorageError): boolean {
  if (!error) {
    return false;
  }
  const status = Number(error.statusCode ?? error.status);
  if (status === 404) {
    return true;
  }
  return /not found|does not exist/i.test(error.message ?? '');
}
