export function userFacingEquineRelationshipMessage(error: unknown): string {
  const message =
    error && typeof error === 'object' && 'message' in error
      ? String((error as { message?: unknown }).message ?? '')
      : error instanceof Error
        ? error.message
        : '';

  if (message.includes('Authentication required')) {
    return 'Inicia sesión para continuar.';
  }

  if (message.includes('Identity could not be resolved')) {
    return 'No se pudo resolver tu identidad. Completa tus datos básicos e inténtalo de nuevo.';
  }

  return 'No se pudieron cargar tus equinos. Inténtalo de nuevo.';
}
