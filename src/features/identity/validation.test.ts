import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  mapIdentityMarket,
  mapIdentityMarkets,
  mapIdentityRow,
  userFacingIdentityMessage,
} from './identityMarket.ts';
import {
  identityMarketLabel,
  isValidCountryCode,
  isValidDateOfBirth,
  isValidIdentityName,
  normalizeCountryCode,
} from './validation.ts';

describe('identity validation', () => {
  it('accepts a real past calendar date', () => {
    assert.equal(isValidDateOfBirth('2000-01-02'), true);
    assert.equal(isValidIdentityName('Ana'), true);
  });

  it('rejects invalid or future dates', () => {
    assert.equal(isValidDateOfBirth(''), false);
    assert.equal(isValidDateOfBirth('02-01-2000'), false);
    assert.equal(isValidDateOfBirth('2020-13-01'), false);
    assert.equal(isValidDateOfBirth('2099-01-01'), false);
  });

  it('normalizes an explicit country code and rejects other shapes', () => {
    assert.equal(normalizeCountryCode(' es '), 'ES');
    assert.equal(isValidCountryCode('es'), true);
    assert.equal(isValidCountryCode(''), false);
    assert.equal(isValidCountryCode('Spain'), false);
    assert.equal(isValidCountryCode('E1'), false);
    assert.equal(identityMarketLabel('ES'), 'España');
    assert.equal(identityMarketLabel('QD'), 'QD');
  });
});

describe('identity market mapping', () => {
  it('maps a caller identity with an explicit country', () => {
    const identity = mapIdentityRow({
      user_account_id: 'account',
      person_id: 'person',
      first_name: 'Ana',
      last_name: 'Example',
      date_of_birth: '1990-01-01',
      country_code: 'ES',
      is_complete: true,
    });

    assert.equal(identity.countryCode, 'ES');
    assert.equal(identity.isComplete, true);
  });

  it('keeps a null country incomplete and fails closed on a bad market row', () => {
    const identity = mapIdentityRow({
      user_account_id: 'account',
      person_id: 'person',
      first_name: 'Ana',
      last_name: 'Example',
      date_of_birth: '1990-01-01',
      country_code: null,
      is_complete: false,
    });

    assert.equal(identity.countryCode, null);
    assert.equal(identity.isComplete, false);
    assert.throws(() => mapIdentityMarket({ country_code: 'Spain', default_locale: 'es-ES' }));
    assert.throws(() => mapIdentityMarkets({ country_code: 'ES' }));
  });

  it('does not echo a database error', () => {
    const message = userFacingIdentityMessage(
      new Error('duplicate key value violates unique constraint market_age_rules'),
    );

    assert.equal(message.includes('market_age_rules'), false);
    assert.equal(message.includes('duplicate key'), false);
    assert.equal(message.includes('Identity market'), false);
  });
});
