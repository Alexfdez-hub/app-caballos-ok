import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  getAuthRedirectAllowList,
  interpretAuthCallbackUrl,
  isAuthCallbackUrl,
  parseAuthCallbackParams,
} from './authCallback.ts';

describe('auth callback URLs', () => {
  it('recognizes Expo Go, web, and native callback URLs', () => {
    assert.equal(
      isAuthCallbackUrl('exp://192.168.1.24:8081/--/auth/callback?code=abc'),
      true,
    );
    assert.equal(
      isAuthCallbackUrl('http://localhost:8081/auth/callback#type=recovery'),
      true,
    );
    assert.equal(isAuthCallbackUrl('app-caballos-ok://auth/callback'), true);
    assert.equal(isAuthCallbackUrl('app-caballos-ok:///auth/callback'), true);
    assert.equal(isAuthCallbackUrl('exp://192.168.1.24:8081'), false);
    assert.equal(isAuthCallbackUrl('http://localhost:8081/'), false);
  });

  it('parses hash and query error params', () => {
    const query = parseAuthCallbackParams(
      'exp://127.0.0.1:8081/--/auth/callback?error=access_denied&error_description=expired',
    );
    assert.equal(query.error, 'access_denied');
    assert.equal(query.error_description, 'expired');

    const hash = parseAuthCallbackParams(
      'http://localhost:8081/auth/callback#error=otp_expired&error_code=otp_expired&type=recovery',
    );
    assert.equal(hash.error, 'otp_expired');
    assert.equal(hash.type, 'recovery');
  });

  it('surfaces invalid or expired callback links instead of ignoring them', () => {
    const expired = interpretAuthCallbackUrl(
      'app-caballos-ok://auth/callback?error=otp_expired&error_description=Token%20has%20expired&type=recovery',
    );
    assert.equal(expired.status, 'error');
    if (expired.status === 'error') {
      assert.equal(expired.type, 'recovery');
      assert.equal(expired.error.code, 'otp_expired');
    }

    const missing = interpretAuthCallbackUrl(
      'http://localhost:8081/auth/callback',
    );
    assert.equal(missing.status, 'error');
    if (missing.status === 'error') {
      assert.equal(missing.error.code, 'access_denied');
    }
  });

  it('keeps recovery type when exchanging tokens', () => {
    const tokens = interpretAuthCallbackUrl(
      'app-caballos-ok://auth/callback#access_token=aaa&refresh_token=bbb&type=recovery',
    );
    assert.equal(tokens.status, 'tokens');
    if (tokens.status === 'tokens') {
      assert.equal(tokens.type, 'recovery');
      assert.equal(tokens.accessToken, 'aaa');
      assert.equal(tokens.refreshToken, 'bbb');
    }
  });

  it('ignores unrelated deep links', () => {
    assert.deepEqual(interpretAuthCallbackUrl('exp://192.168.1.24:8081'), {
      status: 'ignored',
    });
  });

  it('publishes a path-constrained allow-list without a global exp://** wildcard', () => {
    const allowList = getAuthRedirectAllowList();
    assert.deepEqual(allowList, [
      'app-caballos-ok://auth/callback',
      'app-caballos-ok:///auth/callback',
      'http://localhost:8081/auth/callback',
      'http://127.0.0.1:8081/auth/callback',
      'exp://**/--/auth/callback',
    ]);
    assert.equal(allowList.includes('exp://**'), false);
  });
});
