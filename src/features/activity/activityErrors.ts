export function userFacingActivityMessage(error: unknown): string {
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

  return 'No se pudo cargar tu actividad. Inténtalo de nuevo.';
}

export function userFacingMutationMessage(error: unknown): string {
  const code =
    error && typeof error === 'object' && 'code' in error
      ? String((error as { code?: unknown }).code ?? '')
      : '';
  const message =
    error && typeof error === 'object' && 'message' in error
      ? String((error as { message?: unknown }).message ?? '')
      : error instanceof Error
        ? error.message
        : '';

  if (message.includes('Authentication required') || code === '42501') {
    return message.includes('Authentication required')
      ? 'Inicia sesión para continuar.'
      : 'No tienes autoridad para esta acción.';
  }

  if (message.includes('Identity could not be resolved')) {
    return 'No se pudo resolver tu identidad. Completa tus datos básicos e inténtalo de nuevo.';
  }

  if (message.includes('Only an APPROVED booking can be confirmed')) {
    return 'Solo se puede confirmar una reserva ya aprobada.';
  }

  return 'No se pudo completar la acción. Inténtalo de nuevo.';
}
