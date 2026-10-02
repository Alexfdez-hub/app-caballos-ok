import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  AUTH_NATIVE_REDIRECT_URI,
  getAuthRedirectAllowList,
  interpretAuthCallbackUrl,
  isAuthCallbackUrl,
  parseAuthCallbackParams,
  selectAuthRedirectUrl,
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

  it('selects the Expo Go callback from makeRedirectUri path only', () => {
    const calls: Array<{ scheme?: string; path?: string }> = [];
    const url = selectAuthRedirectUrl({
      platformOs: 'android',
      executionEnvironment: 'storeClient',
      makeRedirectUri: (options) => {
        calls.push(options);
        return 'exp://192.0.2.10:8081/--/auth/callback';
      },
    });

    assert.deepEqual(calls, [{ path: 'auth/callback' }]);
    assert.equal(url, 'exp://192.0.2.10:8081/--/auth/callback');
    assert.equal(isAuthCallbackUrl(url), true);
  });

  it('keeps the custom scheme for development builds, standalone apps, and web scheme options', () => {
    for (const executionEnvironment of ['bare', 'standalone', null, undefined]) {
      let called = false;
      const url = selectAuthRedirectUrl({
        platformOs: 'ios',
        executionEnvironment,
        makeRedirectUri: () => {
          called = true;
          return 'exp://192.0.2.10:8081/--/auth/callback';
        },
      });
      assert.equal(called, false);
      assert.equal(url, AUTH_NATIVE_REDIRECT_URI);
    }

    const webCalls: Array<{ scheme?: string; path?: string }> = [];
    const webUrl = selectAuthRedirectUrl({
      platformOs: 'web',
      executionEnvironment: 'storeClient',
      makeRedirectUri: (options) => {
        webCalls.push(options);
        return 'http://localhost:8081/auth/callback';
      },
    });
    assert.deepEqual(webCalls, [
      { scheme: 'app-caballos-ok', path: 'auth/callback' },
    ]);
    assert.equal(webUrl, 'http://localhost:8081/auth/callback');
  });

  it('keeps a recovery code from an Expo Go callback', () => {
    const callback = interpretAuthCallbackUrl(
      'exp://192.0.2.10:8081/--/auth/callback?code=recovery-code&type=recovery',
    );
    assert.equal(callback.status, 'code');
    if (callback.status === 'code') {
      assert.equal(callback.type, 'recovery');
      assert.equal(callback.code, 'recovery-code');
    }
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
