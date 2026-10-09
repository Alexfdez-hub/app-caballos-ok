export const SPAIN_REVIEW_SCOPE = 'MARKET' as const;
export const SPAIN_REVIEW_MARKET = 'ES' as const;

export type ReviewCapability = {
  scopeType: typeof SPAIN_REVIEW_SCOPE;
  marketCountryCode: typeof SPAIN_REVIEW_MARKET;
};

export type ReviewQueueItem = {
  caseId: string;
  caseType: string;
  marketCountryCode: string;
  state: string;
  updatedAt: string;
  evidenceCategories: string[];
};

export type ReviewEvidenceItem = {
  category: string;
  documentCountryCode: string | null;
};

export type ReviewCaseDetail = {
  caseId: string;
  caseType: string;
  state: string;
  marketCountryCode: string;
  createdAt: string;
  updatedAt: string;
  subjectName: string | null;
  equineId: string | null;
  equineName: string | null;
  relationType: string | null;
  relationRole: string | null;
  evidence: ReviewEvidenceItem[];
  evidenceSufficient: boolean;
};

export type ReviewDetailView =
  | { kind: 'none' }
  | { kind: 'unavailable' }
  | { kind: 'ready'; detail: ReviewCaseDetail };

export type ReviewScreenView =
  | { kind: 'signed_out' }
  | { kind: 'loading' }
  | { kind: 'unauthorized' }
  | { kind: 'suspended' }
  | { kind: 'error'; message: string }
  | { kind: 'empty' }
  | { kind: 'queue'; items: ReviewQueueItem[]; detail: ReviewDetailView };
