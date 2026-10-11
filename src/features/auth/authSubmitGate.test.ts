import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  beginAuthOperation,
  endAuthOperation,
  resetAuthOperations,
} from './authSubmitGate.ts';

describe('auth submit gate', () => {
  it('lets one press start one request', async () => {
    resetAuthOperations();
    let calls = 0;

    async function submit() {
      if (!beginAuthOperation('signIn')) {
        return;
      }

      try {
        calls += 1;
        await Promise.resolve();
      } finally {
        endAuthOperation('signIn');
      }
    }

    await submit();
    assert.equal(calls, 1);
  });

  it('collapses rapid signup and recovery presses into one request each', async () => {
    resetAuthOperations();
    const calls = { signUp: 0, recover: 0 };

    async function submit(operation: 'signUp' | 'recover') {
      if (!beginAuthOperation(operation)) {
        return;
      }

      try {
        calls[operation] += 1;
        await new Promise((resolve) => setTimeout(resolve, 20));
      } finally {
        endAuthOperation(operation);
      }
    }

    await Promise.all([
      submit('signUp'),
      submit('signUp'),
      submit('signUp'),
      submit('signUp'),
      submit('recover'),
      submit('recover'),
      submit('recover'),
    ]);

    assert.deepEqual(calls, { signUp: 1, recover: 1 });

    await submit('signUp');
    assert.equal(calls.signUp, 2);
  });
});
