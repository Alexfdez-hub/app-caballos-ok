import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  SIGNED_READ_TTL_SECONDS,
  adaptServerClient,
  handleEquinePhoto,
  serverClientOptions,
  userClientOptions,
} from '../../../supabase/functions/_shared/equinePhoto.ts';
import type {
  InspectedObject,
  PhotoDeps,
  RpcResult,
  ServerPhotoClient,
  UserPhotoClient,
} from '../../../supabase/functions/_shared/equinePhoto.ts';

const equineId = '03210000-0000-4000-8000-0000000000aa';
const mediaId = '03210000-0000-4000-8000-0000000000bb';
const callerAuthUserId = '03210000-0000-4000-8000-000000000001';
const canonicalPath = `${equineId}/${mediaId}`;
const token = 'header.payload.signature-token';
const directMutations = [
  'abandon_my_equine_photo',
  'record_my_equine_photo_finalized',
  'retire_my_equine_photo_metadata',
];
const signedUploadUrl = 'https://storage.example/upload-token';
const signedReadUrl = 'https://storage.example/read-token';

function request(body: unknown, authorization = `Bearer ${token}`) {
  return new Request('http://localhost/function', {
    method: 'POST',
    headers: {
      Authorization: authorization,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
}

function harness(options?: {
  rpc?: UserPhotoClient['rpc'];
  authUserId?: string | null;
  server?: Partial<ServerPhotoClient>;
  mutate?: ServerPhotoClient['mutateMetadata'];
}) {
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const serverCalls: string[] = [];
  const serverMutations: Array<{ name: string; mediaId: string; authUserId: string }> = [];
  let serverCreated = 0;
  const userJwts: string[] = [];
  const logs: unknown[][] = [];
  const original = {
    log: console.log,
    info: console.info,
    warn: console.warn,
    error: console.error,
  };
  for (const method of ['log', 'info', 'warn', 'error'] as const) {
    console[method] = (...args: unknown[]) => {
      logs.push(args);
    };
  }

  const server: ServerPhotoClient = {
    async signUpload(path) {
      serverCalls.push(`upload:${path}`);
      return { signedUrl: signedUploadUrl };
    },
    async signRead(path, expiresIn) {
      serverCalls.push(`read:${path}:${expiresIn}`);
      return { signedUrl: signedReadUrl };
    },
    async inspect() {
      serverCalls.push('inspect');
      return {
        state: 'present',
        contentType: 'image/jpeg',
        size: 1024,
      } satisfies InspectedObject;
    },
    async deleteObject(path) {
      serverCalls.push(`delete:${path}`);
      return 'deleted';
    },
    async mutateMetadata(name, mediaId, authUserId) {
      serverMutations.push({ name, mediaId, authUserId });
      if (options?.mutate) {
        return options.mutate(name, mediaId, authUserId);
      }
      return { data: null, errorMessage: null };
    },
    ...options?.server,
  };
  server.mutateMetadata = async (name, mediaId, authUserId) => {
    serverMutations.push({ name, mediaId, authUserId });
    if (options?.mutate) {
      return options.mutate(name, mediaId, authUserId);
    }
    return { data: null, errorMessage: null };
  };

  const deps: PhotoDeps = {
    createUserClient(jwt) {
      userJwts.push(jwt);
      return {
        async authenticatedUserId() {
          return options && 'authUserId' in options
            ? options.authUserId ?? null
            : callerAuthUserId;
        },
        async rpc(name, args) {
          rpcCalls.push({ name, args });
          if (directMutations.includes(name)) {
            throw new Error('direct client mutation');
          }
          if (options?.rpc) {
            return options.rpc(name, args);
          }
          if (name === 'authorize_my_equine_photo_prepare') {
            return {
              data: [{ media_id: mediaId, storage_path: canonicalPath }],
              errorMessage: null,
            } satisfies RpcResult;
          }
          return { data: canonicalPath, errorMessage: null };
        },
      };
    },
    createServerClient() {
      serverCreated += 1;
      return server;
    },
  };

  return {
    deps,
    rpcCalls,
    serverCalls,
    serverMutations,
    userJwts,
    logs,
    serverCreated: () => serverCreated,
    restore() {
      console.log = original.log;
      console.info = original.info;
      console.warn = original.warn;
      console.error = original.error;
    },
  };
}

describe('equine photo edge boundary', () => {
  it('signs only the path SQL returned and keeps the upload TTL platform-defined', async () => {
    const photo = harness();
    try {
      const response = await handleEquinePhoto(
        'prepare',
        request({
          equineId,
          isPrimary: true,
          contentType: 'image/png',
        }),
        photo.deps,
      );
      assert.equal(response.status, 200);
      assert.equal(response.body.storagePath, canonicalPath);
      assert.equal(response.body.signedUploadUrl, signedUploadUrl);
      assert.equal('expiresIn' in response.body, false);
      assert.deepEqual(photo.serverCalls, [`upload:${canonicalPath}`]);
      assert.deepEqual(photo.userJwts, [token]);
      assert.equal(JSON.stringify(photo.logs).includes(signedUploadUrl), false);
      assert.equal(JSON.stringify(photo.logs).includes(token), false);
    } finally {
      photo.restore();
    }
  });

  it('refuses a request-body path before creating a server client', async () => {
    const photo = harness();
    const response = await handleEquinePhoto(
      'prepare',
      request({
        equineId,
        isPrimary: false,
        contentType: 'image/jpeg',
        storagePath: 'client/path',
      }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 400);
    assert.equal(response.body.error, 'invalid_photo');
    assert.equal(photo.serverCreated(), 0);
    assert.equal(photo.rpcCalls.length, 0);
  });

  it('does not prepare metadata when the caller JWT cannot be validated', async () => {
    const photo = harness({ authUserId: null });
    const response = await handleEquinePhoto(
      'prepare',
      request({ equineId, isPrimary: true, contentType: 'image/jpeg' }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 401);
    assert.equal(photo.rpcCalls.length, 0);
    assert.equal(photo.serverCreated(), 0);
  });

  it('does not sign when prepare authorization fails', async () => {
    const photo = harness({
      rpc: async () => ({
        data: null,
        errorMessage: 'Equine photo is not available',
      }),
    });
    const response = await handleEquinePhoto(
      'prepare',
      request({ equineId, isPrimary: true, contentType: 'image/webp' }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 403);
    assert.equal(response.body.error, 'unavailable');
    assert.equal(JSON.stringify(response.body).includes('Equine photo'), false);
    assert.equal(photo.serverCreated(), 0);
  });

  it('records a valid object and does not delete it when metadata recording fails', async () => {
    const photo = harness({
      mutate: async (name) => {
        if (name === 'record_my_equine_photo_finalized') {
          return { data: null, errorMessage: 'statement timeout' };
        }
        return { data: null, errorMessage: null };
      },
    });
    const response = await handleEquinePhoto(
      'finalize',
      request({ mediaId }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 503);
    assert.equal(response.body.error, 'retry');
    assert.deepEqual(photo.serverCalls, ['inspect']);
    assert.deepEqual(
      photo.serverMutations.map((call) => call.name),
      ['record_my_equine_photo_finalized'],
    );
    assert.equal(
      photo.rpcCalls.some((call) => directMutations.includes(call.name)),
      false,
    );
  });

  it('does not abandon metadata when storage inspection fails', async () => {
    const photo = harness({
      server: {
        async inspect() {
          return { state: 'error' };
        },
      },
    });
    const response = await handleEquinePhoto(
      'finalize',
      request({ mediaId }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 503);
    assert.deepEqual(
      photo.rpcCalls.map((call) => call.name),
      ['authorize_my_equine_photo_finalize'],
    );
    assert.equal(photo.serverMutations.length, 0);
  });

  it('abandons metadata when the object is absent', async () => {
    const photo = harness({
      server: {
        async inspect() {
          return { state: 'absent' };
        },
      },
    });
    const response = await handleEquinePhoto(
      'finalize',
      request({ mediaId }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 200);
    assert.equal(response.body.abandoned, true);
    assert.deepEqual(photo.serverMutations, [
      {
        name: 'abandon_my_equine_photo',
        mediaId,
        authUserId: callerAuthUserId,
      },
    ]);
    assert.deepEqual(
      photo.rpcCalls.map((call) => call.name),
      ['authorize_my_equine_photo_finalize'],
    );
  });

  it('deletes an oversized object before abandoning its metadata', async () => {
    const photo = harness({
      server: {
        async inspect() {
          return { state: 'present', contentType: 'image/jpeg', size: 8 * 1024 * 1024 + 1 };
        },
      },
    });
    const response = await handleEquinePhoto(
      'finalize',
      request({ mediaId }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 200);
    assert.equal(photo.serverCalls.includes(`delete:${canonicalPath}`), true);
    assert.equal(photo.serverMutations.at(-1)?.name, 'abandon_my_equine_photo');
    assert.equal(
      photo.rpcCalls.some((call) => directMutations.includes(call.name)),
      false,
    );
  });

  it('signs a read URL for 300 seconds and returns none when the object is absent', async () => {
    const present = harness();
    const ok = await handleEquinePhoto('read', request({ mediaId }), present.deps);
    present.restore();
    assert.equal(ok.body.expiresIn, SIGNED_READ_TTL_SECONDS);
    assert.deepEqual(present.serverCalls, ['inspect', `read:${canonicalPath}:300`]);

    const missing = harness({
      server: {
        async inspect() {
          return { state: 'absent' };
        },
      },
    });
    const denied = await handleEquinePhoto('read', request({ mediaId }), missing.deps);
    missing.restore();
    assert.equal(denied.status, 409);
    assert.equal('signedReadUrl' in denied.body, false);
    assert.deepEqual(missing.serverCalls, []);
  });

  it('does not retire metadata when object deletion fails', async () => {
    const photo = harness({
      server: {
        async deleteObject() {
          return 'error';
        },
      },
    });
    const response = await handleEquinePhoto(
      'retire',
      request({ mediaId }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 503);
    assert.deepEqual(
      photo.rpcCalls.map((call) => call.name),
      ['authorize_my_equine_photo_retire'],
    );
    assert.equal(photo.serverMutations.length, 0);
  });

  it('retries metadata retirement when the object is already absent', async () => {
    const photo = harness({
      server: {
        async deleteObject() {
          return 'absent';
        },
      },
    });
    const response = await handleEquinePhoto(
      'retire',
      request({ mediaId }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 200);
    assert.deepEqual(photo.serverMutations, [
      {
        name: 'retire_my_equine_photo_metadata',
        mediaId,
        authUserId: callerAuthUserId,
      },
    ]);
    assert.equal(
      photo.rpcCalls.some((call) => directMutations.includes(call.name)),
      false,
    );
  });

  it('abandons the new row when signed upload creation fails', async () => {
    const photo = harness({
      server: {
        async signUpload() {
          return { error: true };
        },
      },
    });
    const response = await handleEquinePhoto(
      'prepare',
      request({ equineId, isPrimary: true, contentType: 'image/jpeg' }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 503);
    assert.equal(response.body.error, 'retry');
    assert.equal('signedUploadUrl' in response.body, false);
    assert.equal('mediaId' in response.body, false);
    assert.deepEqual(photo.serverMutations, [
      {
        name: 'abandon_my_equine_photo',
        mediaId,
        authUserId: callerAuthUserId,
      },
    ]);
    assert.deepEqual(
      photo.rpcCalls.map((call) => call.name),
      ['authorize_my_equine_photo_prepare'],
    );
  });

  it('returns the media id for reconciliation when upload cleanup fails', async () => {
    const photo = harness({
      server: {
        async signUpload() {
          return { error: true };
        },
      },
      mutate: async () => ({ data: null, errorMessage: 'statement timeout' }),
    });
    const response = await handleEquinePhoto(
      'prepare',
      request({ equineId, isPrimary: true, contentType: 'image/jpeg' }),
      photo.deps,
    );
    photo.restore();
    assert.equal(response.status, 503);
    assert.deepEqual(response.body, { error: 'retry', mediaId });
    assert.equal('signedUploadUrl' in response.body, false);
    assert.deepEqual(
      photo.serverMutations.map((call) => call.name),
      ['abandon_my_equine_photo'],
    );
  });

  it('refuses a client identity and never calls a metadata mutation from the user client', async () => {
    const injected = harness();
    const rejected = await handleEquinePhoto(
      'finalize',
      request({ mediaId, authUserId: '03210000-0000-4000-8000-000000000002' }),
      injected.deps,
    );
    injected.restore();
    assert.equal(rejected.status, 400);
    assert.equal(injected.rpcCalls.length, 0);
    assert.equal(injected.serverCreated(), 0);

    const photo = harness();
    const finalized = await handleEquinePhoto('finalize', request({ mediaId }), photo.deps);
    const retired = await handleEquinePhoto('retire', request({ mediaId }), photo.deps);
    photo.restore();
    assert.equal(finalized.status, 200);
    assert.equal(retired.status, 200);
    assert.deepEqual(
      photo.rpcCalls.map((call) => call.name),
      ['authorize_my_equine_photo_finalize', 'authorize_my_equine_photo_retire'],
    );
    assert.deepEqual(
      photo.serverMutations.map((call) => call.authUserId),
      [callerAuthUserId, callerAuthUserId],
    );
  });

  it('keeps the user client on the anon key and the server client on the service role', () => {
    assert.equal(userClientOptions(token).global.headers.Authorization, `Bearer ${token}`);
    assert.equal('global' in serverClientOptions(), false);
    const calls: Array<{ key: string; authorization?: string }> = [];
    const createClient = (_url: string, key: string, options: { global?: { headers?: { Authorization?: string } } }) => {
      calls.push({ key, authorization: options.global?.headers?.Authorization });
      return { storage: {} };
    };
    const env = {
      url: 'http://127.0.0.1:54321',
      anonKey: 'anon-key',
      serviceRoleKey: 'service-role-key',
    };
    const userOptions = userClientOptions(token);
    const serverOptions = serverClientOptions();
    createClient(env.url, env.anonKey, userOptions);
    createClient(env.url, env.serviceRoleKey, serverOptions);
    assert.deepEqual(calls, [
      { key: 'anon-key', authorization: `Bearer ${token}` },
      { key: 'service-role-key', authorization: undefined },
    ]);
  });
});

describe('storage adapter', () => {
  it('treats not-found as absent and any other storage failure as an error', async () => {
    const storage = adaptServerClient({
      async createSignedUploadUrl() {
        return { data: { signedUrl: signedUploadUrl }, error: null };
      },
      async createSignedUrl(_path, expiresIn) {
        assert.equal(expiresIn, 300);
        return { data: { signedUrl: signedReadUrl }, error: null };
      },
      async info() {
        return { data: null, error: { message: 'Object not found', statusCode: 404 } };
      },
      async remove() {
        return { data: null, error: { message: 'network down', status: 500 } };
      },
    });
    assert.deepEqual(await storage.inspect(canonicalPath), { state: 'absent' });
    assert.equal(await storage.deleteObject(canonicalPath), 'error');
  });
});
