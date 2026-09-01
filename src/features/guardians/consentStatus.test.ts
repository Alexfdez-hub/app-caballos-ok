import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  consentDisplayStatus,
  isConsentCurrentlyValid,
} from './consentStatus.ts';

describe('consent effective status', () => {
  const now = new Date('2026-09-01T12:00:00.000Z');

  it('treats stored ACTIVE with a past expiresAt as expired without changing stored status', () => {
    const consent = {
      status: 'ACTIVE' as const,
      expiresAt: '2026-09-01T11:59:00.000Z',
    };

    assert.equal(isConsentCurrentlyValid(consent, now), false);
    assert.equal(consentDisplayStatus(consent, now), 'EXPIRED');
    assert.equal(consent.status, 'ACTIVE');
  });

  it('keeps stored ACTIVE without expiry as currently valid', () => {
    const consent = { status: 'ACTIVE' as const, expiresAt: null };

    assert.equal(isConsentCurrentlyValid(consent, now), true);
    assert.equal(consentDisplayStatus(consent, now), 'ACTIVE');
  });
});
