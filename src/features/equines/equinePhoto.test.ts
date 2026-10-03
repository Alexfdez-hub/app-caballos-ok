import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  MAX_EQUINE_PHOTO_BYTES,
  SIGNED_READ_TTL_SECONDS,
  derivePhotoPanel,
  loadEquinePhotoCards,
  mediaIdsNeedingRefresh,
  nextReadRefreshDelayMs,
  photoPanelAfterListFailure,
  photoResultFromInvoke,
  refreshEquinePhotoRead,
  retireEquinePhoto,
  selectedPhotoFromParts,
  uploadEquinePhoto,
  userFacingEquinePhotoMessage,
  visiblePhotoCards,
} from './equinePhoto.ts';
import type {
  EquinePhotoFunctionName,
  EquinePhotoGateway,
  PhotoCallResult,
  SelectedEquinePhoto,
} from './equinePhoto.ts';

const equineId = '03410000-0000-4000-8000-0000000000aa';
const mediaId = '03410000-0000-4000-8000-0000000000bb';
const signedUploadUrl = 'https://storage.example/object/upload/sign/equine-media/token';
const signedReadUrl = 'https://storage.example/object/sign/equine-media/token';
const refreshedReadUrl = 'https://storage.example/object/sign/equine-media/refreshed';

const photoRow = {
  media_id: mediaId,
  storage_path: `${equineId}/${mediaId}`,
  sort_order: 0,
  is_primary: true,
  created_at: '2026-10-03T00:00:00.000Z',
};

function jpeg(size = 32): SelectedEquinePhoto {
  return selectedPhotoFromParts({
    mimeType: 'image/jpeg',
    fileName: null,
    bytes: new Uint8Array(size).fill(1),
  });
}

function gateway(options?: {
  list?: unknown;
  listError?: unknown;
  invoke?: (
    name: EquinePhotoFunctionName,
    body: Record<string, unknown>,
    call: number,
  ) => PhotoCallResult | Promise<PhotoCallResult>;
  uploadError?: unknown;
}) {
  const calls: Array<{ name: EquinePhotoFunctionName; body: Record<string, unknown> }> = [];
  const uploads: Array<{ url: string; contentType: string; size: number }> = [];
  const invokeCounts = new Map<string, number>();
  const client: EquinePhotoGateway = {
    async listPhotos() {
      if (options?.listError) {
        throw options.listError;
      }
      return options?.list ?? [];
    },
    async invoke(name, body) {
      const call = (invokeCounts.get(name) ?? 0) + 1;
      invokeCounts.set(name, call);
      calls.push({ name, body });
      if (options?.invoke) {
        return options.invoke(name, body, call);
      }
      if (name === 'prepare-my-equine-photo') {
        return {
          status: 200,
          body: { mediaId, storagePath: `${equineId}/${mediaId}`, signedUploadUrl },
        };
      }
      if (name === 'sign-my-equine-photo-read') {
        return {
          status: 200,
          body: { mediaId, signedReadUrl, expiresIn: SIGNED_READ_TTL_SECONDS },
        };
      }
      return { status: 200, body: { mediaId } };
    },
    async uploadSigned(url, contentType, bytes) {
      if (options?.uploadError) {
        throw options.uploadError;
      }
      uploads.push({ url, contentType, size: bytes.byteLength });
    },
  };
  return { client, calls, uploads };
}

describe('equine photo success', () => {
  it('prepares, uploads only the signed URL, and finalizes once', async () => {
    const photo = gateway();
    const uploaded = await uploadEquinePhoto(photo.client, {
      equineId,
      isPrimary: true,
      photo: jpeg(),
    });

    assert.equal(uploaded.mediaId, mediaId);
    assert.deepEqual(
      photo.calls.map((call) => call.name),
      ['prepare-my-equine-photo', 'finalize-my-equine-photo'],
    );
    assert.deepEqual(photo.calls[0]?.body, {
      equineId,
      isPrimary: true,
      contentType: 'image/jpeg',
    });
    assert.deepEqual(photo.calls[1]?.body, { mediaId });
    assert.deepEqual(photo.uploads, [
      { url: signedUploadUrl, contentType: 'image/jpeg', size: 32 },
    ]);
    assert.equal(JSON.stringify(photo.calls).includes('storagePath'), false);
  });

  it('lists one photo and signs a 300 second read', async () => {
    const nowMs = 1_700_000_000_000;
    const photo = gateway({ list: [photoRow] });
    const cards = await loadEquinePhotoCards(photo.client, equineId, nowMs);

    assert.equal(cards.length, 1);
    assert.equal(cards[0]?.read.status, 'ready');
    if (cards[0]?.read.status === 'ready') {
      assert.equal(cards[0].read.signedReadUrl, signedReadUrl);
      assert.equal(cards[0].read.expiresAtMs, nowMs + 300_000);
    }
    assert.equal('storagePath' in (cards[0] ?? {}), false);
    assert.deepEqual(photo.calls, [
      { name: 'sign-my-equine-photo-read', body: { mediaId } },
    ]);
  });
});

describe('equine photo empty loading and error', () => {
  it('keeps an empty list empty and does not sign a read', async () => {
    const photo = gateway({ list: [] });
    const cards = await loadEquinePhotoCards(photo.client, equineId, 0);
    assert.deepEqual(cards, []);
    assert.equal(photo.calls.length, 0);
    assert.equal(
      derivePhotoPanel({ isLoading: false, errorMessage: null, photoCount: 0 }),
      'empty',
    );
  });

  it('hides cards while loading and does not fabricate rows on error', () => {
    const stale = [{ mediaId }];
    assert.equal(
      derivePhotoPanel({ isLoading: true, errorMessage: null, photoCount: stale.length }),
      'loading',
    );
    assert.deepEqual(visiblePhotoCards('loading', stale), []);

    const failed = photoPanelAfterListFailure({
      message: 'duplicate key value violates unique constraint secret',
    });
    assert.equal(failed.phase, 'error');
    assert.deepEqual(failed.photos, []);
    assert.equal(failed.errorMessage.includes('duplicate key'), false);
    assert.equal(failed.errorMessage.includes('secret'), false);
    assert.deepEqual(visiblePhotoCards(failed.phase, stale), []);
    assert.equal(
      derivePhotoPanel({
        isLoading: false,
        errorMessage: failed.errorMessage,
        photoCount: failed.photos.length,
      }),
      'error',
    );
  });

  it('does not echo database text from a list failure', async () => {
    const photo = gateway({
      listError: { message: 'syntax error at or near "select" from equine_media' },
    });
    await assert.rejects(
      () => loadEquinePhotoCards(photo.client, equineId, 0),
      (error: unknown) => {
        const message = userFacingEquinePhotoMessage(error);
        assert.equal(message.includes('syntax'), false);
        assert.equal(message.includes('equine_media'), false);
        assert.match(message, /No se pudo completar la foto/);
        return true;
      },
    );
  });
});

describe('equine photo MIME and size', () => {
  it('refuses a GIF and a file over 8 MiB before any network call', async () => {
    const photo = gateway();
    assert.throws(
      () =>
        selectedPhotoFromParts({
          mimeType: 'image/gif',
          fileName: 'horse.jpg',
          bytes: Uint8Array.of(1, 2, 3),
        }),
      { code: 'invalid_photo' },
    );
    assert.throws(
      () =>
        selectedPhotoFromParts({
          mimeType: 'image/png',
          fileName: null,
          bytes: new Uint8Array(MAX_EQUINE_PHOTO_BYTES + 1),
        }),
      { code: 'invalid_photo' },
    );
    assert.throws(
      () =>
        selectedPhotoFromParts({
          mimeType: 'image/webp',
          fileName: null,
          bytes: new Uint8Array(0),
        }),
      { code: 'invalid_photo' },
    );

    await assert.rejects(
      () =>
        uploadEquinePhoto(photo.client, {
          equineId,
          isPrimary: true,
          photo: {
            mimeType: 'image/gif' as SelectedEquinePhoto['mimeType'],
            sizeBytes: 3,
            bytes: Uint8Array.of(1, 2, 3),
          },
        }),
    );
    assert.equal(photo.calls.length, 0);
    assert.equal(photo.uploads.length, 0);
  });

  it('accepts JPEG, PNG, WebP and exactly 8 MiB', () => {
    assert.equal(
      selectedPhotoFromParts({
        mimeType: 'image/jpg',
        fileName: null,
        bytes: Uint8Array.of(9),
      }).mimeType,
      'image/jpeg',
    );
    assert.equal(
      selectedPhotoFromParts({
        mimeType: null,
        fileName: 'caballo.WEBP',
        bytes: Uint8Array.of(9),
      }).mimeType,
      'image/webp',
    );
    assert.equal(
      selectedPhotoFromParts({
        mimeType: 'image/png',
        fileName: null,
        bytes: new Uint8Array(MAX_EQUINE_PHOTO_BYTES),
      }).sizeBytes,
      MAX_EQUINE_PHOTO_BYTES,
    );
  });
});

describe('equine photo read refresh', () => {
  it('replaces an expired signed read and keeps the 300 second TTL', async () => {
    const issuedAt = 5_000;
    const photo = gateway({
      invoke(name, _body, call) {
        assert.equal(name, 'sign-my-equine-photo-read');
        return {
          status: 200,
          body: {
            mediaId,
            signedReadUrl: call === 1 ? signedReadUrl : refreshedReadUrl,
            expiresIn: SIGNED_READ_TTL_SECONDS,
          },
        };
      },
    });

    const first = await refreshEquinePhotoRead(photo.client, mediaId, issuedAt);
    const expiredAt = first.expiresAtMs;
    assert.equal(expiredAt - issuedAt, SIGNED_READ_TTL_SECONDS * 1000);
    assert.deepEqual(mediaIdsNeedingRefresh([{ mediaId, expiresAtMs: expiredAt }], expiredAt), [
      mediaId,
    ]);
    assert.equal(nextReadRefreshDelayMs([expiredAt], expiredAt), 0);
    assert.deepEqual(
      mediaIdsNeedingRefresh([{ mediaId, expiresAtMs: expiredAt }], expiredAt - 1),
      [],
    );

    const refreshed = await refreshEquinePhotoRead(photo.client, mediaId, expiredAt);
    assert.equal(refreshed.signedReadUrl, refreshedReadUrl);
    assert.notEqual(refreshed.signedReadUrl, first.signedReadUrl);
    assert.equal(refreshed.expiresAtMs, expiredAt + SIGNED_READ_TTL_SECONDS * 1000);
    assert.equal(photo.calls.length, 2);
  });

  it('does not render a public URL or a TTL other than 300 seconds', async () => {
    const publicUrl = gateway({
      invoke() {
        return {
          status: 200,
          body: {
            mediaId,
            signedReadUrl: 'https://storage.example/object/public/equine-media/photo',
            expiresIn: SIGNED_READ_TTL_SECONDS,
          },
        };
      },
    });
    await assert.rejects(() => refreshEquinePhotoRead(publicUrl.client, mediaId, 0));

    const longTtl = gateway({
      invoke() {
        return {
          status: 200,
          body: { mediaId, signedReadUrl, expiresIn: 3600 },
        };
      },
    });
    await assert.rejects(() => refreshEquinePhotoRead(longTtl.client, mediaId, 0));
  });
});

describe('equine photo finalize and retire retry', () => {
  it('retries finalize once and does not upload again', async () => {
    const photo = gateway({
      invoke(name, _body, call) {
        if (name === 'finalize-my-equine-photo' && call === 1) {
          return { status: 503, body: { error: 'retry' } };
        }
        if (name === 'finalize-my-equine-photo') {
          return { status: 200, body: { mediaId } };
        }
        return {
          status: 200,
          body: { mediaId, storagePath: `${equineId}/${mediaId}`, signedUploadUrl },
        };
      },
    });

    const uploaded = await uploadEquinePhoto(photo.client, {
      equineId,
      isPrimary: false,
      photo: jpeg(),
    });
    assert.equal(uploaded.mediaId, mediaId);
    assert.deepEqual(
      photo.calls.map((call) => call.name),
      ['prepare-my-equine-photo', 'finalize-my-equine-photo', 'finalize-my-equine-photo'],
    );
    assert.equal(photo.uploads.length, 1);
  });

  it('stops when finalize abandons the photo', async () => {
    const photo = gateway({
      invoke(name) {
        if (name === 'finalize-my-equine-photo') {
          return { status: 200, body: { mediaId, abandoned: true } };
        }
        return {
          status: 200,
          body: { mediaId, storagePath: `${equineId}/${mediaId}`, signedUploadUrl },
        };
      },
    });
    await assert.rejects(
      () =>
        uploadEquinePhoto(photo.client, {
          equineId,
          isPrimary: true,
          photo: jpeg(),
        }),
      (error: unknown) => {
        assert.equal(userFacingEquinePhotoMessage(error).includes(mediaId), false);
        assert.match(userFacingEquinePhotoMessage(error), /no se guardó/i);
        return true;
      },
    );
    assert.equal(
      photo.calls.filter((call) => call.name === 'finalize-my-equine-photo').length,
      1,
    );
  });

  it('retries retire once and does not prepare or upload', async () => {
    const photo = gateway({
      invoke(_name, _body, call) {
        if (call === 1) {
          return { status: 503, body: { error: 'retry' } };
        }
        return { status: 200, body: { mediaId } };
      },
    });
    await retireEquinePhoto(photo.client, mediaId);
    assert.deepEqual(photo.calls, [
      { name: 'retire-my-equine-photo', body: { mediaId } },
      { name: 'retire-my-equine-photo', body: { mediaId } },
    ]);
    assert.equal(photo.uploads.length, 0);
  });

  it('reads a retry status from the function response without its message', async () => {
    const result = await photoResultFromInvoke({
      data: null,
      error: {
        message: 'relation "equine_media" does not exist',
        context: {
          status: 503,
          async json() {
            return { error: 'retry' };
          },
        },
      },
    });
    assert.deepEqual(result, { status: 503, body: { error: 'retry' } });
    assert.equal(userFacingEquinePhotoMessage({ message: result.body.error }).includes('relation'), false);
  });
});

describe('equine photo client boundary', () => {
  it('does not reference a service key, a public object URL builder, or a bucket read', () => {
    const directory = dirname(fileURLToPath(import.meta.url));
    const source = [
      'equinePhoto.ts',
      'equinePhotoService.ts',
      'selectEquinePhoto.ts',
      'useEquinePhotos.ts',
      '../../screens/EquineDetailScreen.tsx',
      '../../screens/CreateEquineScreen.tsx',
      '../../screens/MyEquinesScreen.tsx',
    ]
      .map((file) => readFileSync(join(directory, file), 'utf8'))
      .join('\n');

    assert.equal(source.includes('service_role'), false);
    assert.equal(source.includes('getPublicUrl'), false);
    assert.equal(source.includes("from('equine-media')"), false);
    assert.equal(source.includes('storage.from'), false);
    assert.equal(source.includes('createSignedUrl'), false);
  });
});
