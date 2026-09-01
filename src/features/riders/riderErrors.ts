export function userFacingRiderMessage(error: unknown): string {
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

  if (message.includes('Profile visibility must be PRIVATE or PUBLIC')) {
    return 'La visibilidad del perfil no es válida.';
  }

  if (message.includes('Experience start year is invalid')) {
    return 'El año de inicio de experiencia no es válido.';
  }

  if (message.includes('Bio is too long')) {
    return 'La biografía es demasiado larga.';
  }

  return 'No se pudo guardar el perfil de jinete. Inténtalo de nuevo.';
}
