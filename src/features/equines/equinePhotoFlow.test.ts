import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  equinePhotoListState,
  finalizeUploadedPhoto,
  refreshEquinePhotoRead,
  retireEquinePhoto,
  uploadEquinePhoto,
  userFacingEquinePhotoMessage,
  validateSelectedPhoto,
} from './equinePhotoFlow.ts';
import type { PhotoGateway, SelectedEquinePhoto } from './equinePhotoFlow.ts';

const equineId = '03410000-0000-4000-8000-0000000000aa';
const mediaId = '03410000-0000-4000-8000-0000000000bb';
const storagePath = `${equineId}/${mediaId}`;

function jpeg(size = 4): SelectedEquinePhoto {
  return {
    contentType: 'image/jpeg',
    size,
    bytes: new Uint8Array(size),
  };
}

function gateway(overrides: Partial<PhotoGateway> = {}): PhotoGateway & {
  calls: string[];
} {
  const calls: string[] = [];
  return {
    calls,
    async prepare() {
      calls.push('prepare');
      return {
        mediaId,
        storagePath,
        signedUploadUrl: 'https://storage.example/upload',
      };
    },
    async upload() {
      calls.push('upload');
      return { ok: true };
    },
    async finalize() {
      calls.push('finalize');
      return { ok: true };
    },
    async signRead() {
      calls.push('sign');
      return {
        signedReadUrl: 'https://storage.example/read',
        expiresIn: 300,
      };
    },
    async retire() {
      calls.push('retire');
      return { ok: true };
    },
    async list() {
      calls.push('list');
      return [];
    },
    ...overrides,
  };
}

describe('equine photo pilot flow', () => {
  it('prepares, uploads and finalizes a valid photo', async () => {
    const photoGateway = gateway();
    const result = await uploadEquinePhoto({
      equineId,
      photo: jpeg(),
      isPrimary: true,
      gateway: photoGateway,
    });
    assert.deepEqual(result, { status: 'ready', mediaId });
    assert.deepEqual(photoGateway.calls, ['prepare', 'upload', 'finalize']);
  });

  it('describes empty, loading and error list states', () => {
    assert.equal(
      equinePhotoListState({ isLoading: true, errorMessage: null, count: 0 }),
      'loading',
    );
    assert.equal(
      equinePhotoListState({ isLoading: false, errorMessage: null, count: 0 }),
      'empty',
    );
    assert.equal(
      equinePhotoListState({
        isLoading: false,
        errorMessage: 'No se pudo completar la foto. Inténtalo de nuevo.',
        count: 2,
      }),
      'error',
    );
  });

  it('rejects a disallowed type and an oversized file before prepare', async () => {
    const gif = await uploadEquinePhoto({
      equineId,
      photo: { contentType: 'image/gif', size: 4, bytes: new Uint8Array(4) },
      isPrimary: false,
      gateway: gateway(),
    });
    assert.equal(gif.status, 'invalid');
    assert.match(gif.status === 'invalid' ? gif.message : '', /JPEG, PNG o WebP/);

    const huge = validateSelectedPhoto({
      contentType: 'image/png',
      size: 8 * 1024 * 1024 + 1,
      bytes: new Uint8Array(1),
    });
    assert.equal(huge?.status, 'invalid');
    assert.match(huge?.message ?? '', /8 MB/);
  });

  it('does not echo a database error', () => {
    assert.equal(
      userFacingEquinePhotoMessage('duplicate key value violates unique constraint secret'),
      'No se pudo completar la foto. Inténtalo de nuevo.',
    );
  });

  it('refreshes an expired read and keeps a current one', async () => {
    const current = {
      mediaId,
      signedReadUrl: 'https://storage.example/read',
      expiresIn: 300,
      signedAt: 1_000,
    };
    const photoGateway = gateway();
    const kept = await refreshEquinePhotoRead({
      mediaId,
      current,
      now: 1_000 + 299_000,
      gateway: photoGateway,
    });
    assert.equal(photoGateway.calls.length, 0);
    assert.equal('signedReadUrl' in kept && kept.signedReadUrl, current.signedReadUrl);

    const refreshed = await refreshEquinePhotoRead({
      mediaId,
      current,
      now: 1_000 + 300_000,
      gateway: photoGateway,
    });
    assert.deepEqual(photoGateway.calls, ['sign']);
    assert.equal('signedAt' in refreshed && refreshed.signedAt, 1_000 + 300_000);
  });

  it('retries finalize and retire without preparing again', async () => {
    let finalizeAttempts = 0;
    const photoGateway = gateway({
      async finalize() {
        finalizeAttempts += 1;
        photoGateway.calls.push('finalize');
        return finalizeAttempts === 1 ? { error: 'retry' } : { ok: true };
      },
      async retire() {
        photoGateway.calls.push('retire');
        return photoGateway.calls.filter((call) => call === 'retire').length === 1
          ? { error: 'retry' }
          : { ok: true };
      },
    });

    const first = await finalizeUploadedPhoto(mediaId, photoGateway);
    assert.equal(first.status, 'retry');
    const second = await finalizeUploadedPhoto(mediaId, photoGateway);
    assert.deepEqual(second, { status: 'ready', mediaId });

    const retireFirst = await retireEquinePhoto(mediaId, photoGateway);
    assert.equal(retireFirst.status, 'retry');
    const retireSecond = await retireEquinePhoto(mediaId, photoGateway);
    assert.deepEqual(retireSecond, { status: 'ready' });
    assert.equal(photoGateway.calls.includes('prepare'), false);
  });
});
