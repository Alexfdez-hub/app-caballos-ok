const EXPECTED_AUTH_CODES = new Set([
  'invalid_credentials',
  'email_not_confirmed',
  'over_email_send_rate_limit',
  'email_address_invalid',
  'email_address_not_authorized',
  'user_already_exists',
  'weak_password',
  'same_password',
  'otp_expired',
  'flow_state_expired',
  'flow_state_not_found',
  'refresh_token_not_found',
  'session_not_found',
  'validation_failed',
  'access_denied',
  'unexpected_failure',
  'user_repeated_signup',
]);

const NETWORK_ERROR_PATTERN =
  /network request failed|failed to fetch|network error|fetch failed|internet connection|err_network/i;

const MAILER_ERROR_PATTERN =
  /error sending (confirmation|recovery) email|error sending email/i;

function isDevEnvironment() {
  if (typeof __DEV__ !== 'undefined') {
    return __DEV__;
  }

  return process.env.NODE_ENV !== 'production';
}

export function getAuthErrorName(error: unknown) {
  if (error && typeof error === 'object' && 'name' in error) {
    return String((error as { name?: unknown }).name ?? '');
  }

  if (error instanceof Error) {
    return error.name;
  }

  return '';
}

export function getAuthErrorMessage(error: unknown) {
  if (error && typeof error === 'object' && 'message' in error) {
    return String((error as { message?: unknown }).message ?? '');
  }

  if (error instanceof Error) {
    return error.message;
  }

  return '';
}

export function getAuthErrorCode(error: unknown) {
  if (error && typeof error === 'object') {
    const record = error as { code?: unknown; error_code?: unknown };
    const code = record.code ?? record.error_code;
    return code == null ? '' : String(code);
  }

  return '';
}

export function getAuthErrorStatus(error: unknown) {
  if (error && typeof error === 'object' && 'status' in error) {
    const status = (error as { status?: unknown }).status;
    return typeof status === 'number' ? status : null;
  }

  return null;
}

export function isMailerAuthError(error: unknown) {
  const message = getAuthErrorMessage(error);
  const code = getAuthErrorCode(error);

  return (
    MAILER_ERROR_PATTERN.test(message) ||
    (code === 'unexpected_failure' && /email/i.test(message))
  );
}

export function isNetworkAuthError(error: unknown) {
  const name = getAuthErrorName(error);
  const message = getAuthErrorMessage(error);
  const status = getAuthErrorStatus(error);

  if (status !== null && status > 0) {
    return false;
  }

  return (
    name === 'AuthRetryableFetchError' ||
    status === 0 ||
    NETWORK_ERROR_PATTERN.test(name) ||
    NETWORK_ERROR_PATTERN.test(message)
  );
}

export function isExpectedAuthError(error: unknown) {
  if (isNetworkAuthError(error) || isMailerAuthError(error)) {
    return true;
  }

  const code = getAuthErrorCode(error);
  const message = getAuthErrorMessage(error);
  const status = getAuthErrorStatus(error);
  const name = getAuthErrorName(error);

  if (EXPECTED_AUTH_CODES.has(code) || name === 'AuthCallbackError') {
    return true;
  }

  if (
    /invalid login credentials|email not confirmed|rate limit|not authorized|already registered|weak password|otp expired|access denied/i.test(
      message,
    )
  ) {
    return true;
  }

  return status !== null && status >= 400 && status < 500;
}

function formatAuthDiagnostic(action: string, error: unknown) {
  return `[auth] ${action} name=${getAuthErrorName(error)} status=${getAuthErrorStatus(error) ?? ''} code=${getAuthErrorCode(error)} message=${getAuthErrorMessage(error)}`;
}

export function logAuthFailure(action: string, error: unknown) {
  const line = formatAuthDiagnostic(action, error);

  if (isExpectedAuthError(error)) {
    if (isDevEnvironment()) {
      console.log(line);
    }
    return;
  }

  console.error(line);
}

export function logUnexpectedAuthFailure(action: string, error: unknown) {
  logAuthFailure(action, error);
}

export function userFacingAuthMessage(
  action:
    | 'signIn'
    | 'signUp'
    | 'resend'
    | 'recover'
    | 'updatePassword'
    | 'callback',
  error: unknown,
) {
  const message = getAuthErrorMessage(error);
  const code = getAuthErrorCode(error);

  if (isNetworkAuthError(error)) {
    return 'No se pudo conectar con el servidor. Comprueba la conexión e inténtalo de nuevo.';
  }

  const status = getAuthErrorStatus(error);
  const isEmailAction =
    action === 'recover' || action === 'resend' || action === 'signUp';

  if (
    isMailerAuthError(error) ||
    (isEmailAction &&
      ((status !== null && status >= 500) || code === 'unexpected_failure'))
  ) {
    return 'No pudimos enviar el correo en este momento. Inténtalo más tarde.';
  }

  if (code === 'email_not_confirmed' || /email not confirmed/i.test(message)) {
    return 'Confirma tu correo antes de iniciar sesión.';
  }

  if (code === 'invalid_credentials' || /invalid login credentials/i.test(message)) {
    return 'Correo o contraseña incorrectos.';
  }

  if (code === 'user_repeated_signup') {
    return 'Si ya tenías cuenta, inicia sesión o restablece la contraseña.';
  }

  if (
    code === 'over_email_send_rate_limit' ||
    /rate limit/i.test(message)
  ) {
    return 'Se han enviado demasiados correos en poco tiempo. Espera unos minutos e inténtalo de nuevo.';
  }

  if (
    code === 'email_address_not_authorized' ||
    /not authorized/i.test(message)
  ) {
    return 'No pudimos enviar el correo en este momento. Inténtalo más tarde.';
  }

  if (code === 'email_address_invalid' || /email address .* is invalid/i.test(message)) {
    return 'Ese correo no es válido. Revisa que esté bien escrito.';
  }

  if (code === 'weak_password' || /weak password/i.test(message)) {
    return 'La contraseña es demasiado débil. Usa al menos 6 caracteres.';
  }

  if (code === 'same_password') {
    return 'La nueva contraseña debe ser distinta de la actual.';
  }

  if (
    action === 'callback' ||
    code === 'otp_expired' ||
    code === 'access_denied'
  ) {
    return 'El enlace de acceso no es válido o ha caducado. Solicita uno nuevo.';
  }

  if (action === 'updatePassword') {
    return 'No se pudo actualizar la contraseña. El enlace puede haber caducado. Solicita uno nuevo.';
  }

  if (action === 'recover' || action === 'resend') {
    return 'No pudimos enviar el correo en este momento. Inténtalo más tarde.';
  }

  return action === 'signUp'
    ? 'No se pudo crear la cuenta. Revisa los datos e inténtalo de nuevo.'
    : 'No se pudo iniciar sesión. Revisa tus datos e inténtalo de nuevo.';
}
