import type {
  CenterMembership,
  CenterMembershipGroup,
  CenterRoleCode,
  MembershipStatus,
} from './types';

export function isCenterRoleCode(value: unknown): value is CenterRoleCode {
  return (
    value === 'ADMIN' ||
    value === 'MANAGER' ||
    value === 'INSTRUCTOR' ||
    value === 'ASSESSOR'
  );
}

export function isMembershipStatus(value: unknown): value is MembershipStatus {
  return value === 'ACTIVE' || value === 'ENDED';
}

export function centerRoleLabel(roleCode: CenterRoleCode): string {
  switch (roleCode) {
    case 'ADMIN':
      return 'Administrador';
    case 'MANAGER':
      return 'Gestor';
    case 'INSTRUCTOR':
      return 'Instructor';
    case 'ASSESSOR':
      return 'Evaluador';
  }
}

export function membershipStatusLabel(status: MembershipStatus): string {
  switch (status) {
    case 'ACTIVE':
      return 'Activa';
    case 'ENDED':
      return 'Finalizada';
  }
}

export function groupMembershipsByCenter(
  memberships: CenterMembership[],
): CenterMembershipGroup[] {
  const groups = new Map<string, CenterMembershipGroup>();

  for (const membership of memberships) {
    const existing = groups.get(membership.centerId);
    if (existing) {
      existing.memberships.push(membership);
      continue;
    }

    groups.set(membership.centerId, {
      centerId: membership.centerId,
      centerName: membership.centerName,
      memberships: [membership],
    });
  }

  return [...groups.values()].sort((left, right) => {
    const leftActive = left.memberships.some(
      (membership) => membership.status === 'ACTIVE',
    );
    const rightActive = right.memberships.some(
      (membership) => membership.status === 'ACTIVE',
    );

    if (leftActive !== rightActive) {
      return leftActive ? -1 : 1;
    }

    return left.centerName.localeCompare(right.centerName, 'es');
  });
}
