import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { classifySignUpResult } from './signUpOutcome.ts';

describe('classifySignUpResult', () => {
  it('returns authenticated when a session exists', () => {
    assert.equal(
      classifySignUpResult(
        {
          user: { id: '1', identities: [{ id: '1' }] } as never,
          session: { access_token: 'token' } as never,
        },
        null,
      ),
      'authenticated',
    );
  });

  it('returns existing_email when identities is empty', () => {
    assert.equal(
      classifySignUpResult(
        {
          user: { id: '1', identities: [] } as never,
          session: null,
        },
        null,
      ),
      'existing_email',
    );
  });

  it('returns pending_confirmation when signup succeeded without a session', () => {
    assert.equal(
      classifySignUpResult(
        {
          user: { id: '1', identities: [{ id: '1' }] } as never,
          session: null,
        },
        null,
      ),
      'pending_confirmation',
    );
  });
});
