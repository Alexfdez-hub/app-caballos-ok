import type { EquineType, ManagementRole, OwnershipStatus } from './types';

export function equineTypeLabel(equineType: EquineType): string {
  return equineType === 'HORSE' ? 'Caballo' : 'Poni';
}

export function ownershipStatusLabel(status: OwnershipStatus): string {
  return status === 'ACTIVE' ? 'Activa' : 'Finalizada';
}

export function effectiveRelationStatusLabel(
  storedStatus: OwnershipStatus,
  isCurrentlyEffective: boolean,
): string {
  if (isCurrentlyEffective) {
    return 'Activa';
  }

  if (storedStatus === 'ENDED') {
    return 'Finalizada';
  }

  return 'Aún no vigente';
}

export function managementRoleLabel(role: ManagementRole): string {
  switch (role) {
    case 'PRIMARY_MANAGER':
      return 'Gestor principal';
    case 'CO_MANAGER':
      return 'Cogestor';
    case 'AUTHORIZED_MANAGER':
      return 'Gestor autorizado';
  }
}
