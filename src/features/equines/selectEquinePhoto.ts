import * as ImagePicker from 'expo-image-picker';

import { EquinePhotoClientError, selectedPhotoFromParts } from './equinePhoto';
import type { SelectedEquinePhoto } from './equinePhoto';

export async function selectEquinePhoto(): Promise<SelectedEquinePhoto | null> {
  try {
    await ImagePicker.requestMediaLibraryPermissionsAsync();
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsEditing: false,
      allowsMultipleSelection: false,
      base64: true,
      exif: false,
      quality: 1,
    });
    if (result.canceled) {
      return null;
    }

    const asset = result.assets[0];
    if (!asset?.base64) {
      throw new EquinePhotoClientError('invalid_photo');
    }

    return selectedPhotoFromParts({
      mimeType: asset.mimeType ?? null,
      fileName: asset.fileName ?? null,
      bytes: decodeBase64(asset.base64),
    });
  } catch (error) {
    if (error instanceof EquinePhotoClientError) {
      throw error;
    }
    throw new EquinePhotoClientError('retry');
  }
}

function decodeBase64(value: string): Uint8Array {
  const normalized = value.replace(/\s/g, '');
  if (normalized.length === 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(normalized)) {
    throw new EquinePhotoClientError('invalid_photo');
  }
  const binary = globalThis.atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}
