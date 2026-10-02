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
const canonicalPath = `${equineId}/${mediaId}`;
const token = 'header.payload.signature-token';
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
  server?: Partial<ServerPhotoClient>;
}) {
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const serverCalls: string[] = [];
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
    ...options?.server,
  };

  const deps: PhotoDeps = {
    createUserClient(jwt) {
      userJwts.push(jwt);
      return {
        async rpc(name, args) {
          rpcCalls.push({ name, args });
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
      rpc: async (name) => {
        if (name === 'record_my_equine_photo_finalized') {
          return { data: null, errorMessage: 'statement timeout' };
        }
        return { data: canonicalPath, errorMessage: null };
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
    assert.equal(
      photo.rpcCalls.some((call) => call.name === 'abandon_my_equine_photo'),
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
    assert.equal(photo.rpcCalls.length, 1);
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
    assert.equal(photo.rpcCalls.at(-1)?.name, 'abandon_my_equine_photo');
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
    assert.equal(photo.rpcCalls.at(-1)?.name, 'abandon_my_equine_photo');
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
    assert.equal(photo.rpcCalls.at(-1)?.name, 'retire_my_equine_photo_metadata');
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
