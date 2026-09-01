import type { GuardianConsent, GuardianConsentStatus } from './types';

export function isConsentCurrentlyValid(
  consent: Pick<GuardianConsent, 'status' | 'expiresAt'>,
  now: Date = new Date(),
): boolean {
  if (consent.status !== 'ACTIVE') {
    return false;
  }

  if (!consent.expiresAt) {
    return true;
  }

  return new Date(consent.expiresAt).getTime() > now.getTime();
}

export function consentDisplayStatus(
  consent: Pick<GuardianConsent, 'status' | 'expiresAt'>,
  now: Date = new Date(),
): GuardianConsentStatus {
  if (consent.status === 'REVOKED') {
    return 'REVOKED';
  }

  if (consent.status === 'EXPIRED' || !isConsentCurrentlyValid(consent, now)) {
    return 'EXPIRED';
  }

  return 'ACTIVE';
}

export function consentStatusLabel(status: GuardianConsentStatus): string {
  switch (status) {
    case 'ACTIVE':
      return 'Activo';
    case 'REVOKED':
      return 'Revocado';
    case 'EXPIRED':
      return 'Caducado';
  }
}
