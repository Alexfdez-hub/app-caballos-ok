import { supabase } from '../../services/supabase/client';
import {
  EquinePhotoClientError,
  assertPrivateSignedUrl,
  photoResultFromInvoke,
} from './equinePhoto';
import type { AllowedPhotoMime, EquinePhotoGateway } from './equinePhoto';

export function createEquinePhotoGateway(): EquinePhotoGateway {
  return {
    async listPhotos(equineId) {
      const { data, error } = await supabase.rpc('list_my_equine_photos', {
        p_equine_id: equineId,
      });
      if (error) {
        throw error;
      }
      return data;
    },
    async invoke(name, body) {
      const { data, error } = await supabase.functions.invoke(name, { body });
      return photoResultFromInvoke({ data, error });
    },
    async uploadSigned(url, contentType, bytes) {
      await putSignedPhoto(url, contentType, bytes);
    },
  };
}

export async function putSignedPhoto(
  signedUploadUrl: string,
  contentType: AllowedPhotoMime,
  bytes: Uint8Array,
): Promise<void> {
  assertPrivateSignedUrl(signedUploadUrl);
  const body = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(body).set(bytes);
  const response = await fetch(signedUploadUrl, {
    method: 'PUT',
    headers: {
      'content-type': contentType,
    },
    body: new Blob([body], { type: contentType }),
  });
  if (!response.ok) {
    throw new EquinePhotoClientError('retry');
  }
}
