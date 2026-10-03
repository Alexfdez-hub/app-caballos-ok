import type { Identity, IdentityMarket } from './types';

export const IDENTITY_SAVE_ERROR =
  'No se pudo guardar tu identidad. Inténtalo de nuevo en unos instantes.';

export const IDENTITY_MARKET_LOAD_ERROR =
  'No se pudieron cargar los países. Inténtalo de nuevo en unos instantes.';

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object';
}

function isSelectableCountryCode(value: string): boolean {
  return /^[A-Z]{2}$/.test(value.trim().toUpperCase());
}

export function mapIdentityRow(value: unknown): Identity {
  if (!isRecord(value)) {
    throw new Error('Identity RPC returned an unexpected result.');
  }

  if (
    typeof value.user_account_id !== 'string' ||
    typeof value.person_id !== 'string' ||
    (value.first_name !== null && typeof value.first_name !== 'string') ||
    (value.last_name !== null && typeof value.last_name !== 'string') ||
    (value.date_of_birth !== null && typeof value.date_of_birth !== 'string') ||
    (value.country_code !== null && typeof value.country_code !== 'string') ||
    typeof value.is_complete !== 'boolean'
  ) {
    throw new Error('Identity RPC returned an unexpected result.');
  }

  return {
    userAccountId: value.user_account_id,
    personId: value.person_id,
    firstName: value.first_name,
    lastName: value.last_name,
    dateOfBirth: value.date_of_birth,
    countryCode: value.country_code,
    isComplete: value.is_complete,
  };
}

export function mapIdentityRows(data: unknown): Identity {
  if (!Array.isArray(data) || data.length !== 1) {
    throw new Error('Identity RPC returned an unexpected result.');
  }

  return mapIdentityRow(data[0]);
}

export function mapIdentityMarket(value: unknown): IdentityMarket {
  if (!isRecord(value) || typeof value.country_code !== 'string') {
    throw new Error('Identity market RPC returned an unexpected result.');
  }

  if (!isSelectableCountryCode(value.country_code)) {
    throw new Error('Identity market RPC returned an unexpected result.');
  }

  if (value.default_locale !== null && typeof value.default_locale !== 'string') {
    throw new Error('Identity market RPC returned an unexpected result.');
  }

  return {
    countryCode: value.country_code,
    defaultLocale: value.default_locale,
  };
}

export function mapIdentityMarkets(data: unknown): IdentityMarket[] {
  if (!Array.isArray(data)) {
    throw new Error('Identity market RPC returned an unexpected result.');
  }

  return data.map(mapIdentityMarket);
}

export function userFacingIdentityMessage(error: unknown) {
  void error;
  return IDENTITY_SAVE_ERROR;
}
