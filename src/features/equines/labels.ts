import type { EquineType, ManagementRole, OwnershipStatus } from './types';

export function equineTypeLabel(equineType: EquineType): string {
  return equineType === 'HORSE' ? 'Caballo' : 'Poni';
}

export function ownershipStatusLabel(status: OwnershipStatus): string {
  return status === 'ACTIVE' ? 'Activa' : 'Finalizada';
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
