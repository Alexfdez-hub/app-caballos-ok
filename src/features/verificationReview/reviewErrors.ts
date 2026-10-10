const NEUTRAL_MESSAGE =
  'No se pudo consultar la revisión. Inténtalo de nuevo.';

function rawMessage(error: unknown): string {
  if (error && typeof error === 'object' && 'message' in error) {
    return String((error as { message?: unknown }).message ?? '');
  }

  if (error instanceof Error) {
    return error.message;
  }

  return '';
}

function rawCode(error: unknown): string {
  if (error && typeof error === 'object' && 'code' in error) {
    return String((error as { code?: unknown }).code ?? '');
  }

  return '';
}

export function isReviewDenied(error: unknown): boolean {
  const code = rawCode(error);
  const message = rawMessage(error);

  return (
    code === '42501' ||
    message.includes('Verification request is not available') ||
    message.includes('Authentication required')
  );
}

export function userFacingReviewMessage(error: unknown): string {
  void error;
  return NEUTRAL_MESSAGE;
}
