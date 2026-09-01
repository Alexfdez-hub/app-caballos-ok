export const AUTH_REDIRECT_PATH = 'auth/callback';
export const AUTH_APP_SCHEME = 'app-caballos-ok';
export const AUTH_NATIVE_REDIRECT_URI = `${AUTH_APP_SCHEME}://${AUTH_REDIRECT_PATH}`;
export const AUTH_NATIVE_REDIRECT_URI_TRIPLE = `${AUTH_APP_SCHEME}:///${AUTH_REDIRECT_PATH}`;
export const AUTH_WEB_DEV_PORT = '8081';

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

export type InterpretedAuthCallback =
  | { status: 'ignored' }
  | { status: 'error'; type: string | null; error: AuthCallbackErrorShape }
  | { status: 'code'; type: string | null; code: string }
  | {
      status: 'tokens';
      type: string | null;
      accessToken: string;
      refreshToken: string;
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
