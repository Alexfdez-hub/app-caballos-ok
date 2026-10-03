import { supabase } from '../../services/supabase/client';
import { userFacingEquinePhotoMessage } from './equinePhotoFlow';
import type { EquinePhotoSummary, PhotoGateway } from './equinePhotoFlow';

type FunctionError = { error?: unknown };

function functionCode(data: unknown, error: unknown): string | null {
  if (error) {
    return 'retry';
  }
  if (data && typeof data === 'object' && 'error' in data) {
    const code = (data as FunctionError).error;
    return typeof code === 'string' ? code : 'retry';
  }
  return null;
}

async function invoke(name: string, body: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await supabase.functions.invoke(name, { body });
  const code = functionCode(data, error);
  if (code) {
    throw new Error(code);
  }
  return data;
}

export const equinePhotoGateway: PhotoGateway = {
  async prepare(input) {
    try {
      const data = (await invoke('prepare-my-equine-photo', {
        equineId: input.equineId,
        isPrimary: input.isPrimary,
        contentType: input.contentType,
      })) as {
        mediaId?: unknown;
        storagePath?: unknown;
        signedUploadUrl?: unknown;
      };
      if (
        typeof data.mediaId !== 'string' ||
        typeof data.storagePath !== 'string' ||
        typeof data.signedUploadUrl !== 'string'
      ) {
        return { error: 'retry' };
      }
      return {
        mediaId: data.mediaId,
        storagePath: data.storagePath,
        signedUploadUrl: data.signedUploadUrl,
      };
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'retry' };
    }
  },

  async upload(input) {
    const response = await fetch(input.signedUploadUrl, {
      method: 'PUT',
      headers: {
        'Content-Type': input.contentType,
        'x-upsert': 'false',
      },
      body: input.bytes.buffer.slice(
        input.bytes.byteOffset,
        input.bytes.byteOffset + input.bytes.byteLength,
      ) as ArrayBuffer,
    });
    return response.ok ? { ok: true } : { error: 'retry' };
  },

  async finalize(mediaId) {
    try {
      await invoke('finalize-my-equine-photo', { mediaId });
      return { ok: true };
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'retry' };
    }
  },

  async signRead(mediaId) {
    try {
      const data = (await invoke('sign-my-equine-photo-read', { mediaId })) as {
        signedReadUrl?: unknown;
        expiresIn?: unknown;
      };
      if (typeof data.signedReadUrl !== 'string' || data.expiresIn !== 300) {
        return { error: 'retry' };
      }
      return { signedReadUrl: data.signedReadUrl, expiresIn: data.expiresIn };
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'retry' };
    }
  },

  async retire(mediaId) {
    try {
      await invoke('retire-my-equine-photo', { mediaId });
      return { ok: true };
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'retry' };
    }
  },

  async list(equineId) {
    const { data, error } = await supabase.rpc('list_my_equine_photos', {
      p_equine_id: equineId,
    });
    if (error) {
      return { error: 'retry' };
    }
    const rows = Array.isArray(data) ? data : [];
    const photos: EquinePhotoSummary[] = [];
    for (const row of rows) {
      if (!row || typeof row !== 'object') {
        return { error: 'retry' };
      }
      const record = row as Record<string, unknown>;
      if (
        typeof record.media_id !== 'string' ||
        typeof record.storage_path !== 'string' ||
        typeof record.is_primary !== 'boolean'
      ) {
        return { error: 'retry' };
      }
      photos.push({
        mediaId: record.media_id,
        storagePath: record.storage_path,
        isPrimary: record.is_primary,
      });
    }
    return photos;
  },
};

export function equinePhotoErrorMessage(error: unknown): string {
  return userFacingEquinePhotoMessage(error);
}
