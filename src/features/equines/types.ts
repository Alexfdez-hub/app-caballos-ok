export type EquineType = 'HORSE' | 'PONY';

export type OwnershipStatus = 'ACTIVE' | 'ENDED';

export type ManagementRole =
  | 'PRIMARY_MANAGER'
  | 'CO_MANAGER'
  | 'AUTHORIZED_MANAGER';

export type EquineOwnership = {
  ownershipId: string;
  equineId: string;
  equineName: string;
  equineType: EquineType;
  ownerType: 'PERSON';
  ownershipPercentage: number;
  status: OwnershipStatus;
  startedAt: string;
  endedAt: string | null;
};

export type EquineManagementAssignment = {
  assignmentId: string;
  equineId: string;
  equineName: string;
  equineType: EquineType;
  managementRole: ManagementRole;
  status: OwnershipStatus;
  validFrom: string;
  validUntil: string | null;
};
