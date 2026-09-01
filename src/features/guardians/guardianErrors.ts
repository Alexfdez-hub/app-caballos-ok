export function userFacingGuardianMessage(error: unknown): string {
  const message =
    error && typeof error === 'object' && 'message' in error
      ? String((error as { message?: unknown }).message ?? '')
      : error instanceof Error
        ? error.message
        : '';

  if (message.includes('Required guardian policy has not been accepted')) {
    return 'Falta aceptar la política de tutor. Eso es distinto del consentimiento de actividad.';
  }

  if (message.includes('Guardian relationship is not verified')) {
    return 'Esta relación no está verificada, así que no se puede conceder consentimiento.';
  }

  if (message.includes('Caller is not the guardian')) {
    return 'No puedes gestionar el consentimiento de una relación que no es tuya.';
  }

  if (message.includes('Guardian consent is not required')) {
    return 'El consentimiento de tutor no aplica para esta persona en el mercado indicado.';
  }

  if (message.includes('No effective market age rule')) {
    return 'No hay una regla de edad vigente para evaluar el consentimiento.';
  }

  if (message.includes('Authentication required')) {
    return 'Inicia sesión para continuar.';
  }

  return 'No se pudo completar la acción de tutor. Inténtalo de nuevo.';
}
