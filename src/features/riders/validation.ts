import type { ProfileVisibility } from './types';

const MAX_BIO_LENGTH = 2000;
const MIN_EXPERIENCE_YEAR = 1900;

export function isValidRiderBio(value: string) {
  return value.trim().length <= MAX_BIO_LENGTH;
}

export function isValidExperienceStartYear(
  value: number | null,
  currentYear = new Date().getFullYear(),
) {
  if (value === null) {
    return true;
  }

  return (
    Number.isInteger(value) &&
    value >= MIN_EXPERIENCE_YEAR &&
    value <= currentYear
  );
}

export function parseExperienceStartYear(value: string): number | null {
  const normalized = value.trim();

  if (normalized.length === 0) {
    return null;
  }

  if (!/^\d{4}$/.test(normalized)) {
    return Number.NaN;
  }

  return Number(normalized);
}

export function isProfileVisibility(value: string): value is ProfileVisibility {
  return value === 'PRIVATE' || value === 'PUBLIC';
}
