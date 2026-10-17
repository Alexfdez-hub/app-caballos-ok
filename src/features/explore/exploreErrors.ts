export function userFacingExploreMessage(error: unknown): string {
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

  if (message.includes('Bookable offer is not available')) {
    return 'Esa franja ya no está disponible. Actualiza la lista.';
  }

  if (message.includes('Bookable query range')) {
    return 'El intervalo de búsqueda no es válido.';
  }

  if (message.includes('Booking request outcome is ambiguous')) {
    return 'No se sabe si la solicitud quedó registrada. Reconcíliala antes de volver a enviarla.';
  }

  return 'No se pudo cargar la disponibilidad. Inténtalo de nuevo.';
}
