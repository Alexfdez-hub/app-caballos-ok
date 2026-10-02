import type { ActivityBooking } from './types';

const BOOKING_LABELS: Record<ActivityBooking['bookingStatus'], string> = {
  DRAFT: 'Borrador',
  REQUESTED: 'Solicitada',
  PENDING_REQUIREMENTS: 'Pendiente de requisitos',
  PENDING_APPROVAL: 'Pendiente de aprobación',
  APPROVED: 'Aprobada, pendiente de confirmación',
  CONFIRMED: 'Confirmada',
  ACTIVE: 'En curso',
  COMPLETED: 'Completada',
  REJECTED: 'Rechazada',
  CANCELLED: 'Cancelada',
  EXPIRED: 'Caducada',
  DISPUTED: 'En disputa',
};

export function bookingStatusLabel(status: ActivityBooking['bookingStatus']): string {
  return BOOKING_LABELS[status];
}

export function callerRelationLabel(relation: ActivityBooking['callerRelation']): string {
  if (relation === 'BOOKER') {
    return 'Tu cuenta reservó para otra persona. Su identidad no se muestra aquí.';
  }

  return 'Participas en esta reserva.';
}
