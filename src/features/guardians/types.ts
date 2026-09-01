export type GuardianVerificationStatus =
  | 'PENDING'
  | 'VERIFIED'
  | 'REJECTED'
  | 'REVOKED'
  | 'EXPIRED';

export type GuardianConsentStatus = 'ACTIVE' | 'REVOKED' | 'EXPIRED';

export type GuardianRelationship = {
  id: string;
  minorPersonId: string;
  minorFirstName: string | null;
  minorLastName: string | null;
  relationshipType: string;
  verificationStatus: GuardianVerificationStatus;
  verifiedAt: string | null;
  expiresAt: string | null;
  revokedAt: string | null;
};

export type GuardianConsent = {
  id: string;
  guardianRelationshipId: string;
  minorPersonId: string;
  consentType: string;
  scopeType: string;
  termsVersion: string;
  status: GuardianConsentStatus;
  grantedAt: string;
  expiresAt: string | null;
  revokedAt: string | null;
};
