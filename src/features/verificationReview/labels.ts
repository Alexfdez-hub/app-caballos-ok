const CASE_TYPES: Record<string, string> = {
  IDENTITY: 'Identidad',
  OWNERSHIP: 'Propiedad',
  MANAGEMENT: 'Gestión',
};

const STATES: Record<string, string> = {
  SUBMITTED: 'Enviada',
  IN_REVIEW: 'En revisión',
  RESUBMITTED: 'Reenviada',
};

const CATEGORIES: Record<string, string> = {
  IDENTITY_PROVIDER_REFERENCE: 'Referencia del proveedor de identidad',
  EQUINE_IDENTIFIER_REFERENCE: 'Identificador del equino',
  OWNERSHIP_ARTIFACT: 'Documento de propiedad',
  MANAGEMENT_DELEGATION_ARTIFACT: 'Autorización de gestión',
  CENTER_CORROBORATION: 'Comprobación del centro',
  INSURANCE_REFERENCE: 'Referencia de seguro',
  REVIEWER_NOTE: 'Nota de revisión',
};

const RELATIONS: Record<string, string> = {
  PERSON: 'Persona',
  CENTER: 'Centro',
  OWNER: 'Propiedad',
  PRIMARY_MANAGER: 'Gestión principal',
  CO_MANAGER: 'Cogestión',
  AUTHORIZED_MANAGER: 'Gestión autorizada',
};

const UNAVAILABLE = 'No disponible';

export function reviewLabel(catalog: Record<string, string>, code: string): string {
  return catalog[code] ?? UNAVAILABLE;
}

export function caseTypeLabel(code: string): string {
  return reviewLabel(CASE_TYPES, code);
}

export function caseStateLabel(code: string): string {
  return reviewLabel(STATES, code);
}

export function evidenceCategoryLabel(code: string): string {
  return reviewLabel(CATEGORIES, code);
}

export function relationLabel(code: string | null): string {
  if (!code) {
    return UNAVAILABLE;
  }

  return reviewLabel(RELATIONS, code);
}

export function marketLabel(code: string): string {
  if (code === 'ES') {
    return 'España';
  }

  if (/^[A-Z]{2}$/.test(code)) {
    return code;
  }

  return UNAVAILABLE;
}
