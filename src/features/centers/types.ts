export type CenterRoleCode = 'ADMIN' | 'MANAGER' | 'INSTRUCTOR' | 'ASSESSOR';

export type MembershipStatus = 'ACTIVE' | 'ENDED';

export type CenterMembership = {
  membershipId: string;
  centerId: string;
  centerName: string;
  roleCode: CenterRoleCode;
  status: MembershipStatus;
  joinedAt: string;
  endedAt: string | null;
};

export type CenterMembershipGroup = {
  centerId: string;
  centerName: string;
  memberships: CenterMembership[];
};
