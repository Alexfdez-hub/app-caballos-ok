export const AUTH_REDIRECT_PATH = 'auth/callback';
export const AUTH_APP_SCHEME = 'app-caballos-ok';
export const AUTH_NATIVE_REDIRECT_URI = `${AUTH_APP_SCHEME}://${AUTH_REDIRECT_PATH}`;
export const AUTH_NATIVE_REDIRECT_URI_TRIPLE = `${AUTH_APP_SCHEME}:///${AUTH_REDIRECT_PATH}`;
export const AUTH_WEB_DEV_PORT = '8081';
export const AUTH_EXECUTION_STORE_CLIENT = 'storeClient';

type AuthRedirectUriOptions = {
  scheme?: string;
  path?: string;
};

export function selectAuthRedirectUrl(input: {
  platformOs: string;
  executionEnvironment: string | null | undefined;
  makeRedirectUri: (options: AuthRedirectUriOptions) => string;
}) {
  if (input.platformOs === 'web') {
    return input.makeRedirectUri({
      scheme: AUTH_APP_SCHEME,
      path: AUTH_REDIRECT_PATH,
    });
  }

  if (input.executionEnvironment === AUTH_EXECUTION_STORE_CLIENT) {
    return input.makeRedirectUri({
      path: AUTH_REDIRECT_PATH,
    });
  }

  return AUTH_NATIVE_REDIRECT_URI;
}

export function getAuthRedirectAllowList() {
  return [
    AUTH_NATIVE_REDIRECT_URI,
    AUTH_NATIVE_REDIRECT_URI_TRIPLE,
    `http://localhost:${AUTH_WEB_DEV_PORT}/${AUTH_REDIRECT_PATH}`,
    `http://127.0.0.1:${AUTH_WEB_DEV_PORT}/${AUTH_REDIRECT_PATH}`,
    `exp://**/--/${AUTH_REDIRECT_PATH}`,
  ];
}

export type AuthCallbackErrorShape = {
  name: 'AuthCallbackError';
  message: string;
  code: string;
  status: number;
};

export const AUTH_OTP_TYPES = [
  'signup',
  'invite',
  'magiclink',
  'recovery',
  'email_change',
  'email',
] as const;

export type AuthOtpType = (typeof AUTH_OTP_TYPES)[number];

const CONFIRMATION_OTP_TYPES = new Set<string>([
  'signup',
  'email',
  'magiclink',
  'invite',
]);

export type InterpretedAuthCallback =
  | { status: 'ignored' }
  | { status: 'error'; type: string | null; error: AuthCallbackErrorShape }
  | { status: 'code'; type: string | null; code: string }
  | { status: 'otp'; type: AuthOtpType; tokenHash: string }
  | {
      status: 'tokens';
      type: string | null;
      accessToken: string;
      refreshToken: string;
    };

export type AuthCallbackIntent = 'recovery' | 'confirmation' | 'unknown';

export type AuthLinkGate =
  | 'processing'
  | 'link-error'
  | 'update-password'
  | 'signed-out'
  | 'signed-in';

export type AuthCallbackSessionClient = {
  exchangeCodeForSession: (code: string) => Promise<{
    data: { redirectType?: string | null; session?: unknown } | null;
    error: { message?: string; code?: string; name?: string } | null;
  }>;
  setSession: (tokens: {
    access_token: string;
    refresh_token: string;
  }) => Promise<{ error: { message?: string; code?: string; name?: string } | null }>;
  verifyOtp: (params: {
    token_hash: string;
    type: AuthOtpType;
  }) => Promise<{ error: { message?: string; code?: string; name?: string } | null }>;
};

export type EstablishedAuthCallback = {
  type: string | null;
  redirectType: string | null;
  error: AuthCallbackErrorShape | { message?: string; code?: string; name?: string } | null;
  ignored: boolean;
};

export function parseAuthCallbackParams(url: string) {
  const params: Record<string, string> = {};
  const hashIndex = url.indexOf('#');
  const withoutHash = hashIndex >= 0 ? url.slice(0, hashIndex) : url;
  const hash = hashIndex >= 0 ? url.slice(hashIndex + 1) : '';

  try {
    const parsed = new URL(withoutHash);
    parsed.searchParams.forEach((value, key) => {
      if (value) {
        params[key] = value;
      }
    });
  } catch {
    const queryIndex = withoutHash.indexOf('?');
    if (queryIndex >= 0) {
      new URLSearchParams(withoutHash.slice(queryIndex + 1)).forEach(
        (value, key) => {
          if (value) {
            params[key] = value;
          }
        },
      );
    }
  }

  if (hash) {
    const hashQuery = hash.startsWith('?') ? hash.slice(1) : hash;
    new URLSearchParams(hashQuery).forEach((value, key) => {
      if (value) {
        params[key] = value;
      }
    });
  }

  return params;
}

export function isAuthCallbackUrl(url: string) {
  const normalized = url.split('#')[0] ?? url;

  if (
    normalized.includes(`/--/${AUTH_REDIRECT_PATH}`) ||
    normalized.includes(`/${AUTH_REDIRECT_PATH}`)
  ) {
    return true;
  }

  try {
    const parsed = new URL(normalized);
    const path = `${parsed.hostname}${parsed.pathname}`.replace(/\/+/g, '/');
    return (
      path === `/${AUTH_REDIRECT_PATH}` ||
      path === AUTH_REDIRECT_PATH ||
      path === `/auth/callback` ||
      parsed.pathname === `/${AUTH_REDIRECT_PATH}` ||
      (parsed.protocol === `${AUTH_APP_SCHEME}:` &&
        parsed.hostname === 'auth' &&
        parsed.pathname.replace(/\/$/, '') === '/callback')
    );
  } catch {
    return false;
  }
}

function callbackError(
  code: string,
  message: string,
): AuthCallbackErrorShape {
  return {
    name: 'AuthCallbackError',
    message,
    code,
    status: 400,
  };
}

export function interpretAuthCallbackUrl(url: string): InterpretedAuthCallback {
  if (!isAuthCallbackUrl(url)) {
    return { status: 'ignored' };
  }

  const params = parseAuthCallbackParams(url);
  const type = params.type ?? null;
  const errorCode = params.error ?? params.error_code ?? null;

  if (errorCode) {
    return {
      status: 'error',
      type,
      error: callbackError(
        errorCode,
        params.error_description ?? errorCode,
      ),
    };
  }

  if (params.token_hash) {
    if (!isAuthOtpType(params.type)) {
      return {
        status: 'error',
        type,
        error: callbackError(
          'access_denied',
          'El enlace de acceso no incluye un tipo válido.',
        ),
      };
    }

    return { status: 'otp', type: params.type, tokenHash: params.token_hash };
  }

  if (params.code) {
    return { status: 'code', type, code: params.code };
  }

  if (params.access_token && params.refresh_token) {
    return {
      status: 'tokens',
      type,
      accessToken: params.access_token,
      refreshToken: params.refresh_token,
    };
  }

  return {
    status: 'error',
    type,
    error: callbackError(
      'access_denied',
      'El enlace de acceso no incluye un código válido.',
    ),
  };
}

function readRedirectType(
  data: { redirectType?: string | null } | null,
) {
  return typeof data?.redirectType === 'string' ? data.redirectType : null;
}

function isAuthOtpType(value: string | null | undefined): value is AuthOtpType {
  return typeof value === 'string' && AUTH_OTP_TYPES.some((type) => type === value);
}

export function classifyAuthCallbackIntent(input: {
  urlType: string | null;
  redirectType: string | null;
}): AuthCallbackIntent {
  if (input.urlType === 'recovery') {
    return 'recovery';
  }

  if (input.urlType && CONFIRMATION_OTP_TYPES.has(input.urlType)) {
    return 'confirmation';
  }

  if (input.urlType) {
    return 'unknown';
  }

  if (input.redirectType === 'recovery') {
    return 'recovery';
  }

  if (input.redirectType && CONFIRMATION_OTP_TYPES.has(input.redirectType)) {
    return 'confirmation';
  }

  return 'unknown';
}

export function selectAuthLinkGate(input: {
  hasSession: boolean;
  isPasswordRecovery: boolean;
  isProcessingAuthLink: boolean;
  hasAuthLinkError: boolean;
}): AuthLinkGate {
  if (input.isProcessingAuthLink) {
    return 'processing';
  }

  if (input.hasAuthLinkError) {
    return 'link-error';
  }

  if (input.hasSession && input.isPasswordRecovery) {
    return 'update-password';
  }

  if (!input.hasSession) {
    return 'signed-out';
  }

  return 'signed-in';
}

const TRANSIENT_CALLBACK_PATTERN =
  /network request failed|failed to fetch|network error|fetch failed|internet connection|err_network|timeout|timed out/i;

function callbackErrorName(error: unknown) {
  if (error && typeof error === 'object' && 'name' in error) {
    return String((error as { name?: unknown }).name ?? '');
  }

  if (error instanceof Error) {
    return error.name;
  }

  return '';
}

function callbackErrorMessage(error: unknown) {
  if (error && typeof error === 'object' && 'message' in error) {
    return String((error as { message?: unknown }).message ?? '');
  }

  if (error instanceof Error) {
    return error.message;
  }

  return '';
}

function callbackErrorCode(error: unknown) {
  if (error && typeof error === 'object') {
    const record = error as { code?: unknown; error_code?: unknown };
    const code = record.code ?? record.error_code;
    return code == null ? '' : String(code);
  }

  return '';
}

function callbackErrorStatus(error: unknown) {
  if (error && typeof error === 'object' && 'status' in error) {
    const status = (error as { status?: unknown }).status;
    return typeof status === 'number' ? status : null;
  }

  return null;
}

function isTransientCallbackFailure(error: unknown) {
  const status = callbackErrorStatus(error);
  if (status !== null && status >= 500) {
    return true;
  }

  if (status !== null && status > 0) {
    return false;
  }

  const name = callbackErrorName(error);
  const message = callbackErrorMessage(error);
  return (
    name === 'AuthRetryableFetchError' ||
    status === 0 ||
    TRANSIENT_CALLBACK_PATTERN.test(name) ||
    TRANSIENT_CALLBACK_PATTERN.test(message)
  );
}

const DEFINITIVE_CALLBACK_CODES = new Set([
  'otp_expired',
  'flow_state_expired',
  'flow_state_not_found',
  'access_denied',
  'refresh_token_not_found',
  'session_not_found',
  'pkce_code_verifier_not_found',
  'validation_failed',
]);

const claimedAuthCallbacks = new Map<string, 'in-flight' | 'finalized'>();

export function authCallbackClaimSettlement(error: unknown) {
  if (isTransientCallbackFailure(error)) {
    return 'released' as const;
  }

  const status = callbackErrorStatus(error);
  const name = callbackErrorName(error);
  const code = callbackErrorCode(error);
  const message = callbackErrorMessage(error);

  if (
    name === 'AuthCallbackError' ||
    DEFINITIVE_CALLBACK_CODES.has(code) ||
    (status !== null && status >= 400 && status < 500) ||
    /otp expired|invalid or has expired|access denied|invalid grant/i.test(message)
  ) {
    return 'finalized' as const;
  }

  return 'released' as const;
}

export function authCallbackDedupeKey(url: string) {
  const interpreted = interpretAuthCallbackUrl(url);

  if (interpreted.status === 'ignored') {
    return null;
  }

  if (interpreted.status === 'code') {
    return `code:${interpreted.code}`;
  }

  if (interpreted.status === 'otp') {
    return `otp:${interpreted.tokenHash}`;
  }

  if (interpreted.status === 'tokens') {
    return `access:${interpreted.accessToken}`;
  }

  return `url:${url}`;
}

export function claimAuthCallback(url: string) {
  const key = authCallbackDedupeKey(url);

  if (!key) {
    return 'ignored' as const;
  }

  const current = claimedAuthCallbacks.get(key);
  if (current === 'in-flight' || current === 'finalized') {
    return 'duplicate' as const;
  }

  claimedAuthCallbacks.set(key, 'in-flight');
  return 'claimed' as const;
}

export function settleAuthCallback(
  url: string,
  outcome: 'finalized' | 'released',
) {
  const key = authCallbackDedupeKey(url);

  if (!key || claimedAuthCallbacks.get(key) !== 'in-flight') {
    return;
  }

  if (outcome === 'released') {
    claimedAuthCallbacks.delete(key);
    return;
  }

  claimedAuthCallbacks.set(key, 'finalized');
}

export function shouldReplaceAuthLinkState(
  claim: 'ignored' | 'duplicate' | 'claimed',
) {
  return claim === 'claimed';
}

export function resetAuthCallbackClaims() {
  claimedAuthCallbacks.clear();
}

export function reduceAuthCallbackResult(
  state: { acceptedCallback: boolean; isPasswordRecovery: boolean },
  result: EstablishedAuthCallback,
) {
  if (result.ignored) {
    return { ...state, showError: false };
  }

  if (result.error) {
    return {
      ...state,
      showError: !state.acceptedCallback,
    };
  }

  const intent = classifyAuthCallbackIntent({
    urlType: result.type,
    redirectType: result.redirectType,
  });

  return {
    acceptedCallback: true,
    isPasswordRecovery:
      intent === 'recovery'
        ? true
        : intent === 'confirmation'
          ? false
          : state.isPasswordRecovery,
    showError: false,
  };
}

export async function establishSessionFromCallback(
  interpreted: InterpretedAuthCallback,
  client: AuthCallbackSessionClient,
): Promise<EstablishedAuthCallback> {
  if (interpreted.status === 'ignored') {
    return { type: null, redirectType: null, error: null, ignored: true };
  }

  if (interpreted.status === 'error') {
    return {
      type: interpreted.type,
      redirectType: null,
      error: interpreted.error,
      ignored: false,
    };
  }

  if (interpreted.status === 'otp') {
    const { error } = await client.verifyOtp({
      token_hash: interpreted.tokenHash,
      type: interpreted.type,
    });
    return {
      type: interpreted.type,
      redirectType: null,
      error,
      ignored: false,
    };
  }

  if (interpreted.status === 'code') {
    const { data, error } = await client.exchangeCodeForSession(interpreted.code);
    return {
      type: interpreted.type,
      redirectType: readRedirectType(data),
      error,
      ignored: false,
    };
  }

  const { error } = await client.setSession({
    access_token: interpreted.accessToken,
    refresh_token: interpreted.refreshToken,
  });

  return {
    type: interpreted.type,
    redirectType: null,
    error,
    ignored: false,
  };
}
