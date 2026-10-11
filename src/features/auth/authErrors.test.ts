import assert from 'node:assert/strict';
import { describe, it, mock } from 'node:test';

import { authCallbackClaimSettlement } from './authCallback.ts';
import {
  isExpectedAuthError,
  isMailerAuthError,
  isNetworkAuthError,
  isRetryableAuthCallbackFailure,
  logAuthFailure,
  userFacingAuthMessage,
} from './authErrors.ts';

describe('network auth errors', () => {
  it('treats status 0 AuthRetryableFetchError as connectivity', () => {
    const retryable = {
      name: 'AuthRetryableFetchError',
      message: 'Network request failed',
      status: 0,
    };

    assert.equal(isNetworkAuthError(retryable), true);
    assert.equal(isExpectedAuthError(retryable), true);
    assert.match(
      userFacingAuthMessage('signIn', retryable),
      /No se pudo conectar/,
    );
  });

  it('does not treat a mailer HTTP 500 as a connection failure', () => {
    const mailer = {
      name: 'AuthRetryableFetchError',
      message: 'Error sending recovery email',
      status: 500,
    };

    assert.equal(isNetworkAuthError(mailer), false);
    assert.equal(isMailerAuthError(mailer), true);
    assert.match(userFacingAuthMessage('recover', mailer), /enviar el correo/);
    assert.match(
      userFacingAuthMessage('signUp', {
        name: 'AuthRetryableFetchError',
        message: 'Error sending confirmation email',
        status: 500,
      }),
      /enviar el correo/,
    );
    assert.equal(
      userFacingAuthMessage('signIn', {
        code: 'invalid_credentials',
        message: 'Invalid login credentials',
        status: 400,
      }),
      'Correo o contraseña incorrectos.',
    );
    assert.equal(
      userFacingAuthMessage('signIn', {
        code: 'email_not_confirmed',
        message: 'Email not confirmed',
        status: 400,
      }),
      'Confirma tu correo antes de iniciar sesión.',
    );
  });

  it('does not console.error known connectivity or mailer failures', () => {
    const errorSpy = mock.method(console, 'error', () => {});
    const logSpy = mock.method(console, 'log', () => {});

    logAuthFailure('signIn', {
      name: 'AuthRetryableFetchError',
      message: 'Network request failed',
      status: 0,
    });
    logAuthFailure('recover', {
      name: 'AuthRetryableFetchError',
      message: 'Error sending recovery email',
      status: 500,
    });

    assert.equal(errorSpy.mock.callCount(), 0);
    assert.ok(logSpy.mock.callCount() >= 1);
    errorSpy.mock.restore();
    logSpy.mock.restore();
  });

  it('still logs unexpected server failures', () => {
    const errorSpy = mock.method(console, 'error', () => {});

    logAuthFailure('signIn', {
      name: 'AuthApiError',
      message: 'Internal server error',
      status: 500,
    });

    assert.equal(errorSpy.mock.callCount(), 1);
    errorSpy.mock.restore();
  });
});

describe('expected auth errors', () => {
  it('does not console.error invalid credentials or rate limits', () => {
    const errorSpy = mock.method(console, 'error', () => {});

    logAuthFailure('signIn', {
      message: 'Invalid login credentials',
      code: 'invalid_credentials',
      status: 400,
    });
    logAuthFailure('resend', {
      message: 'email rate limit exceeded',
      code: 'over_email_send_rate_limit',
      status: 429,
    });
    logAuthFailure('signUp', {
      message: 'User already registered',
      code: 'user_repeated_signup',
      status: 422,
    });

    assert.equal(
      userFacingAuthMessage('signUp', {
        message: 'User already registered',
        code: 'user_repeated_signup',
        status: 422,
      }),
      'Si ya tenías cuenta, inicia sesión o restablece la contraseña.',
    );
    assert.doesNotMatch(
      userFacingAuthMessage('signUp', {
        message: 'User already registered',
        code: 'user_repeated_signup',
        status: 422,
      }),
      /cuenta creada|hemos creado|nueva cuenta/i,
    );
    assert.equal(errorSpy.mock.callCount(), 0);
    errorSpy.mock.restore();
  });

  it('tells the user to retry a transient callback and not that the link expired', () => {
    const cases = [
      {
        name: 'AuthRetryableFetchError',
        message: 'Network request failed',
        status: 0,
      },
      new Error('timeout'),
      { name: 'AuthApiError', message: 'upstream timeout', status: 503 },
    ];

    for (const error of cases) {
      assert.equal(isRetryableAuthCallbackFailure(error), true);
      assert.equal(authCallbackClaimSettlement(error), 'released');
      const copy = userFacingAuthMessage('callback', error);
      assert.match(copy, /volver a abrir el enlace/);
      assert.doesNotMatch(copy, /caducado/);
    }

    const expired = {
      name: 'AuthApiError',
      message: 'Email link is invalid or has expired',
      code: 'otp_expired',
      status: 403,
    };
    assert.equal(isRetryableAuthCallbackFailure(expired), false);
    assert.equal(authCallbackClaimSettlement(expired), 'finalized');
    assert.equal(
      userFacingAuthMessage('callback', expired),
      'El enlace de acceso no es válido o ha caducado. Solicita uno nuevo.',
    );
  });

  it('explains a callback opened outside the session that requested it', () => {
    assert.match(
      userFacingAuthMessage('callback', {
        name: 'AuthPKCECodeVerifierMissingError',
        code: 'pkce_code_verifier_not_found',
        message: 'PKCE code verifier not found in storage.',
        status: 400,
      }),
      /misma sesión/,
    );
  });
});
