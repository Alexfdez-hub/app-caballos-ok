import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  isProfileVisibility,
  isValidExperienceStartYear,
  isValidRiderBio,
  parseExperienceStartYear,
} from './validation.ts';

describe('rider profile validation', () => {
  it('accepts an empty or short bio and rejects one over 2000 characters', () => {
    assert.equal(isValidRiderBio(''), true);
    assert.equal(isValidRiderBio('  Jinete amateur  '), true);
    assert.equal(isValidRiderBio('x'.repeat(2000)), true);
    assert.equal(isValidRiderBio(`  ${'x'.repeat(2001)}  `), false);
  });

  it('accepts a documented experience year and rejects Galope-like or future values', () => {
    assert.equal(isValidExperienceStartYear(null, 2026), true);
    assert.equal(isValidExperienceStartYear(2010, 2026), true);
    assert.equal(isValidExperienceStartYear(1900, 2026), true);
    assert.equal(isValidExperienceStartYear(2026, 2026), true);
    assert.equal(isValidExperienceStartYear(1899, 2026), false);
    assert.equal(isValidExperienceStartYear(2027, 2026), false);
    assert.equal(isValidExperienceStartYear(4.5, 2026), false);
  });

  it('parses a four-digit year and treats a blank field as unset', () => {
    assert.equal(parseExperienceStartYear('2012'), 2012);
    assert.equal(parseExperienceStartYear('  '), null);
    assert.ok(Number.isNaN(parseExperienceStartYear('Galope 4')));
    assert.ok(Number.isNaN(parseExperienceStartYear('12')));
  });

  it('accepts only documented visibility values', () => {
    assert.equal(isProfileVisibility('PRIVATE'), true);
    assert.equal(isProfileVisibility('PUBLIC'), true);
    assert.equal(isProfileVisibility('SECRET'), false);
    assert.equal(isProfileVisibility('public'), false);
  });
});
