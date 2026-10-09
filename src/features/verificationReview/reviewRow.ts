import type {
  ReviewCapability,
  ReviewCaseDetail,
  ReviewEvidenceItem,
  ReviewQueueItem,
} from './types';

export class ReviewResponseError extends Error {
  constructor() {
    super('Review response could not be read.');
    this.name = 'ReviewResponseError';
  }
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new ReviewResponseError();
  }

  return value as Record<string, unknown>;
}

function text(value: unknown): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new ReviewResponseError();
  }

  return value;
}

function optionalText(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }

  if (typeof value !== 'string') {
    throw new ReviewResponseError();
  }

  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function textList(value: unknown): string[] {
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) {
    throw new ReviewResponseError();
  }

  return value;
}

function booleanValue(value: unknown): boolean {
  if (typeof value !== 'boolean') {
    throw new ReviewResponseError();
  }

  return value;
}

export function parseReviewCapabilities(data: unknown): ReviewCapability[] {
  if (!Array.isArray(data)) {
    throw new ReviewResponseError();
  }

  return data.map((row) => {
    const item = record(row);

    if (
      item.scope_type !== 'MARKET' ||
      item.market_country_code !== 'ES'
    ) {
      throw new ReviewResponseError();
    }

    return {
      scopeType: 'MARKET',
      marketCountryCode: 'ES',
    };
  });
}

export function parseReviewQueue(data: unknown): ReviewQueueItem[] {
  if (!Array.isArray(data)) {
    throw new ReviewResponseError();
  }

  return data.map((row) => {
    const item = record(row);

    return {
      caseId: text(item.case_id),
      caseType: text(item.case_type),
      marketCountryCode: text(item.market_country_code),
      state: text(item.state),
      updatedAt: text(item.updated_at),
      evidenceCategories: textList(item.evidence_categories),
    };
  });
}

function parseEvidence(value: unknown): ReviewEvidenceItem[] {
  if (!Array.isArray(value)) {
    throw new ReviewResponseError();
  }

  return value.map((row) => {
    const item = record(row);
    const country = item.document_country_code;

    if (
      country !== null &&
      country !== undefined &&
      typeof country !== 'string'
    ) {
      throw new ReviewResponseError();
    }

    return {
      category: text(item.category),
      documentCountryCode:
        typeof country === 'string' && country.trim() !== '' ? country : null,
    };
  });
}

export function parseReviewCase(data: unknown): ReviewCaseDetail {
  if (!Array.isArray(data) || data.length !== 1) {
    throw new ReviewResponseError();
  }

  const item = record(data[0]);

  return {
    caseId: text(item.case_id),
    caseType: text(item.case_type),
    state: text(item.state),
    marketCountryCode: text(item.market_country_code),
    createdAt: text(item.created_at),
    updatedAt: text(item.updated_at),
    subjectName: optionalText(item.subject_name),
    equineId: optionalText(item.equine_id),
    equineName: optionalText(item.equine_name),
    relationType: optionalText(item.relation_type),
    relationRole: optionalText(item.relation_role),
    evidence: parseEvidence(item.evidence),
    evidenceSufficient: booleanValue(item.evidence_sufficient),
  };
}
