import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { isValidDateOfBirth, isValidIdentityName } from './validation.ts';

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
});
