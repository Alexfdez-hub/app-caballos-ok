const GENERIC_MESSAGE =
  'No se pudo completar la verificación. Inténtalo de nuevo.';

const SESSION_MESSAGE = 'Inicia sesión para continuar.';

const PRIVATE_DETAIL =
  /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|select |insert |update |delete |syntax|relation |function |sqlstate|42501|verification_|identity_verification|equine_ownership|equine_management/i;

function rawMessage(error: unknown): string {
  if (error && typeof error === 'object' && 'message' in error) {
    return String((error as { message?: unknown }).message ?? '');
  }

  if (error instanceof Error) {
    return error.message;
  }

  return '';
}

export function userFacingVerificationMessage(error: unknown): string {
  const message = rawMessage(error);

  if (message.includes('Authentication required')) {
    return SESSION_MESSAGE;
  }

  if (PRIVATE_DETAIL.test(message) || message.length === 0) {
    return GENERIC_MESSAGE;
  }

  return GENERIC_MESSAGE;
}

export class VerificationResponseError extends Error {
  constructor() {
    super('Verification response could not be read.');
    this.name = 'VerificationResponseError';
  }
}
