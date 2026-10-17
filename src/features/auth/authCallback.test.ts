import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  AUTH_NATIVE_REDIRECT_URI,
  authCallbackClaimSettlement,
  claimAuthCallback,
  classifyAuthCallbackIntent,
  establishSessionFromCallback,
  getAuthRedirectAllowList,
  interpretAuthCallbackUrl,
  isAuthCallbackUrl,
  parseAuthCallbackParams,
  reduceAuthCallbackResult,
  resetAuthCallbackClaims,
  selectAuthLinkGate,
  selectAuthRedirectUrl,
  settleAuthCallback,
  shouldReplaceAuthLinkState,
  type AuthCallbackSessionClient,
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
    assert.equal(
      isAuthCallbackUrl('http://127.0.0.1:8081/auth/callback?code=abc'),
      true,
    );
  });

  it('accepts only the exact callback path for an admitted environment', () => {
    assert.equal(
      isAuthCallbackUrl('http://localhost:8081/auth/callback'),
      true,
    );
    assert.equal(
      isAuthCallbackUrl('exp://192.0.2.10:8081/--/auth/callback'),
      true,
    );
    assert.equal(
      isAuthCallbackUrl('http://localhost:8081/auth/callback/evil?code=abc'),
      false,
    );
    assert.equal(
      isAuthCallbackUrl('http://localhost:8081/prefix/auth/callback?code=abc'),
      false,
    );
    assert.equal(
      isAuthCallbackUrl('http://localhost:8081/auth/callback-extra?code=abc'),
      false,
    );
    assert.equal(
      isAuthCallbackUrl('exp://192.168.1.24:8081/--/auth/callback/evil'),
      false,
    );
    assert.equal(
      isAuthCallbackUrl(
        'exp://192.168.1.24:8081/--/horses?next=/auth/callback&code=abc',
      ),
      false,
    );
    assert.equal(
      isAuthCallbackUrl('https://evil.example/auth/callback?code=abc'),
      false,
    );
    assert.equal(
      isAuthCallbackUrl('https://evil.example/foo/auth/callback-extra?code=abc'),
      false,
    );
    assert.equal(
      isAuthCallbackUrl('http://localhost:8081/not/auth/callback'),
      false,
    );
    assert.equal(
      isAuthCallbackUrl('http://localhost:8081/auth%2Fcallback?code=abc'),
      false,
    );
    assert.equal(
      isAuthCallbackUrl('http://localhost:8081/auth/callback%2Fevil?code=abc'),
      false,
    );
    assert.equal(
      isAuthCallbackUrl('http://localhost:9090/auth/callback'),
      false,
    );
    assert.equal(
      interpretAuthCallbackUrl(
        'https://evil.example/auth/callback?code=placeholder',
      ).status,
      'ignored',
    );
    assert.equal(
      interpretAuthCallbackUrl(
        'exp://192.0.2.10:8081/--/auth/callback?code=placeholder&type=recovery',
      ).status,
      'code',
    );
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

function unusedClient(method: string): never {
  throw new Error(`${method} should not be called`);
}

function callbackClient(
  overrides: Partial<AuthCallbackSessionClient> = {},
): AuthCallbackSessionClient {
  return {
    exchangeCodeForSession: () => unusedClient('exchangeCodeForSession'),
    setSession: () => unusedClient('setSession'),
    verifyOtp: () => unusedClient('verifyOtp'),
    ...overrides,
  };
}

describe('auth callback delivery', () => {
  it('processes one callback when getInitialURL and Linking deliver the same URL', async () => {
    resetAuthCallbackClaims();
    const url =
      'exp://192.0.2.10:8081/--/auth/callback?code=placeholder-code&type=recovery';
    const calls: string[] = [];
    const client = callbackClient({
      exchangeCodeForSession: async (code) => {
        calls.push(code);
        return { data: { redirectType: 'recovery' }, error: null };
      },
    });

    async function deliver() {
      if (claimAuthCallback(url) !== 'claimed') {
        return null;
      }

      return establishSessionFromCallback(interpretAuthCallbackUrl(url), client);
    }

    const [first, second] = await Promise.all([deliver(), deliver()]);
    assert.equal(calls.length, 1);
    assert.equal(calls[0], 'placeholder-code');
    assert.ok(first);
    assert.equal(second, null);
    assert.equal(
      classifyAuthCallbackIntent({
        urlType: first?.type ?? null,
        redirectType: first?.redirectType ?? null,
      }),
      'recovery',
    );
    assert.equal(
      selectAuthLinkGate({
        hasSession: true,
        isPasswordRecovery: true,
        isProcessingAuthLink: false,
        hasAuthLinkError: false,
      }),
      'update-password',
    );
  });

  it('treats a recovery code without a URL type as recovery only from the stored redirect type', async () => {
    const interpreted = interpretAuthCallbackUrl(
      'exp://192.0.2.10:8081/--/auth/callback?code=placeholder-code',
    );
    assert.equal(interpreted.status, 'code');
    if (interpreted.status !== 'code') {
      return;
    }

    assert.equal(interpreted.type, null);
    const established = await establishSessionFromCallback(
      interpreted,
      callbackClient({
        exchangeCodeForSession: async () => ({
          data: { redirectType: 'recovery' },
          error: null,
        }),
      }),
    );
    const reduced = reduceAuthCallbackResult(
      { acceptedCallback: false, isPasswordRecovery: false },
      established,
    );
    assert.equal(reduced.isPasswordRecovery, true);
    assert.equal(reduced.showError, false);
  });

  it('does not treat signup confirmation as password recovery', async () => {
    assert.equal(
      classifyAuthCallbackIntent({ urlType: 'signup', redirectType: 'recovery' }),
      'confirmation',
    );
    assert.equal(
      classifyAuthCallbackIntent({ urlType: 'email', redirectType: null }),
      'confirmation',
    );

    const interpreted = interpretAuthCallbackUrl(
      'exp://192.0.2.20:8082/--/auth/callback?token_hash=hash-placeholder&type=email',
    );
    assert.equal(interpreted.status, 'otp');
    const calls: string[] = [];
    const established = await establishSessionFromCallback(
      interpreted,
      callbackClient({
        verifyOtp: async (params) => {
          calls.push(params.type);
          return { error: null };
        },
      }),
    );
    assert.deepEqual(calls, ['email']);
    const reduced = reduceAuthCallbackResult(
      { acceptedCallback: false, isPasswordRecovery: true },
      established,
    );
    assert.equal(reduced.isPasswordRecovery, false);
    assert.equal(
      selectAuthLinkGate({
        hasSession: true,
        isPasswordRecovery: reduced.isPasswordRecovery,
        isProcessingAuthLink: false,
        hasAuthLinkError: false,
      }),
      'signed-in',
    );
  });

  it('verifies a recovery token hash without exchanging a code', async () => {
    const interpreted = interpretAuthCallbackUrl(
      'exp://192.0.2.10:8081/--/auth/callback?token_hash=hash-placeholder&type=recovery',
    );
    const calls: string[] = [];
    const established = await establishSessionFromCallback(
      interpreted,
      callbackClient({
        verifyOtp: async (params) => {
          calls.push(params.type);
          return { error: null };
        },
      }),
    );
    assert.deepEqual(calls, ['recovery']);
    assert.equal(established.type, 'recovery');
    assert.equal(
      selectAuthLinkGate({
        hasSession: true,
        isPasswordRecovery: true,
        isProcessingAuthLink: false,
        hasAuthLinkError: false,
      }),
      'update-password',
    );
  });

  it('shows a recoverable error for a consumed callback and a visible processing state', () => {
    const expired = interpretAuthCallbackUrl(
      'exp://192.0.2.10:8081/--/auth/callback?error=otp_expired&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired',
    );
    assert.equal(expired.status, 'error');
    assert.equal(
      selectAuthLinkGate({
        hasSession: false,
        isPasswordRecovery: false,
        isProcessingAuthLink: true,
        hasAuthLinkError: false,
      }),
      'processing',
    );
    assert.equal(
      selectAuthLinkGate({
        hasSession: false,
        isPasswordRecovery: false,
        isProcessingAuthLink: false,
        hasAuthLinkError: true,
      }),
      'link-error',
    );
  });

  it('keeps a successful callback when a later distinct error URL arrives', () => {
    const success = reduceAuthCallbackResult(
      { acceptedCallback: false, isPasswordRecovery: false },
      {
        type: null,
        redirectType: 'recovery',
        error: null,
        ignored: false,
      },
    );
    const afterError = reduceAuthCallbackResult(success, {
      type: 'recovery',
      redirectType: null,
      error: {
        name: 'AuthCallbackError',
        message: 'Email link is invalid or has expired',
        code: 'otp_expired',
        status: 400,
      },
      ignored: false,
    });
    assert.equal(success.isPasswordRecovery, true);
    assert.equal(afterError.showError, false);
    assert.equal(afterError.isPasswordRecovery, true);
  });

  it('accepts the same callback again after a fresh runtime, and a changed tunnel host', () => {
    resetAuthCallbackClaims();
    const previousHost =
      'exp://192.0.2.10:8081/--/auth/callback?code=reopen-placeholder&type=recovery';
    assert.equal(claimAuthCallback(previousHost), 'claimed');
    assert.equal(claimAuthCallback(previousHost), 'duplicate');
    resetAuthCallbackClaims();
    assert.equal(claimAuthCallback(previousHost), 'claimed');

    const currentHost = selectAuthRedirectUrl({
      platformOs: 'android',
      executionEnvironment: 'storeClient',
      makeRedirectUri: () => 'exp://192.0.2.20:8082/--/auth/callback',
    });
    assert.equal(currentHost, 'exp://192.0.2.20:8082/--/auth/callback');
    assert.equal(isAuthCallbackUrl(previousHost), true);
    assert.equal(isAuthCallbackUrl(currentHost), true);
    assert.equal(getAuthRedirectAllowList().includes('exp://**'), false);
  });

  it('retries a transient failure and ignores a callback that already succeeded', async () => {
    resetAuthCallbackClaims();
    const url =
      'exp://192.0.2.10:8081/--/auth/callback?code=retry-placeholder&type=recovery';
    const calls: string[] = [];
    const client = callbackClient({
      exchangeCodeForSession: async (code) => {
        calls.push(code);
        if (calls.length === 1) {
          return {
            data: { redirectType: null, session: null },
            error: {
              name: 'AuthRetryableFetchError',
              message: 'Network request failed',
              status: 0,
            },
          };
        }

        return { data: { redirectType: 'recovery', session: {} }, error: null };
      },
    });

    async function deliver() {
      const claim = claimAuthCallback(url);
      if (!shouldReplaceAuthLinkState(claim)) {
        return claim;
      }

      const established = await establishSessionFromCallback(
        interpretAuthCallbackUrl(url),
        client,
      );
      settleAuthCallback(
        url,
        established.error
          ? authCallbackClaimSettlement(established.error)
          : 'finalized',
      );
      return established;
    }

    const first = await deliver();
    assert.equal(authCallbackClaimSettlement(
      first && typeof first === 'object' && 'error' in first ? first.error : null,
    ), 'released');
    const second = await deliver();
    assert.equal(calls.length, 2);
    assert.ok(second && typeof second === 'object' && 'error' in second);
    if (second && typeof second === 'object' && 'redirectType' in second) {
      assert.equal(second.redirectType, 'recovery');
    }
    assert.equal(await deliver(), 'duplicate');
    assert.equal(calls.length, 2);
  });

  it('keeps a consumed callback finalized and visible without another exchange', async () => {
    resetAuthCallbackClaims();
    const url =
      'exp://192.0.2.10:8081/--/auth/callback?error=otp_expired&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired';
    const calls: string[] = [];
    const client = callbackClient({
      exchangeCodeForSession: async (code) => {
        calls.push(code);
        return { data: null, error: null };
      },
    });
    const claim = claimAuthCallback(url);
    const established = await establishSessionFromCallback(
      interpretAuthCallbackUrl(url),
      client,
    );
    settleAuthCallback(
      url,
      established.error
        ? authCallbackClaimSettlement(established.error)
        : 'finalized',
    );

    assert.equal(claim, 'claimed');
    assert.equal(calls.length, 0);
    assert.equal(authCallbackClaimSettlement(established.error), 'finalized');
    assert.equal(
      reduceAuthCallbackResult(
        { acceptedCallback: false, isPasswordRecovery: false },
        established,
      ).showError,
      true,
    );
    assert.equal(
      selectAuthLinkGate({
        hasSession: false,
        isPasswordRecovery: false,
        isProcessingAuthLink: false,
        hasAuthLinkError: true,
      }),
      'link-error',
    );
    assert.equal(claimAuthCallback(url), 'duplicate');
    assert.equal(calls.length, 0);
  });

  it('does not clear an established error or recovery screen for a duplicate callback', () => {
    assert.equal(shouldReplaceAuthLinkState('duplicate'), false);
    assert.equal(shouldReplaceAuthLinkState('ignored'), false);
    assert.equal(
      selectAuthLinkGate({
        hasSession: false,
        isPasswordRecovery: false,
        isProcessingAuthLink: false,
        hasAuthLinkError: true,
      }),
      'link-error',
    );
    assert.equal(
      selectAuthLinkGate({
        hasSession: true,
        isPasswordRecovery: true,
        isProcessingAuthLink: false,
        hasAuthLinkError: false,
      }),
      'update-password',
    );
  });

  it('releases a thrown recoverable exception and finalizes an expired token response', () => {
    assert.equal(
      authCallbackClaimSettlement(new Error('timeout')),
      'released',
    );
    assert.equal(
      authCallbackClaimSettlement({
        name: 'AuthApiError',
        message: 'Email link is invalid or has expired',
        code: 'otp_expired',
        status: 403,
      }),
      'finalized',
    );
  });
});
