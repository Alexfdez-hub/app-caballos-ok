export type EquineVisibility = 'PRIVATE' | 'PUBLIC';

export type MyEquineSummary = {
  equineId: string;
  equineName: string;
  equineType: 'HORSE' | 'PONY';
  status: 'ACTIVE' | 'INACTIVE' | 'ARCHIVED' | 'DECEASED';
  visibilityStatus: EquineVisibility;
  isOwner: boolean;
  isPrimaryManager: boolean;
};

export type MyEquineDetail = MyEquineSummary & {
  birthDate: string | null;
  sex: string | null;
  breed: string | null;
  heightCm: number | null;
  description: string | null;
  temperamentDescription: string | null;
};

const UNEXPECTED = 'Equine RPC returned an unexpected result.';

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object';
}

function isEquineType(value: unknown): value is 'HORSE' | 'PONY' {
  return value === 'HORSE' || value === 'PONY';
}

function isStatus(
  value: unknown,
): value is MyEquineSummary['status'] {
  return (
    value === 'ACTIVE' ||
    value === 'INACTIVE' ||
    value === 'ARCHIVED' ||
    value === 'DECEASED'
  );
}

function isVisibility(value: unknown): value is EquineVisibility {
  return value === 'PRIVATE' || value === 'PUBLIC';
}

function optionalText(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function optionalNumber(value: unknown): number | null {
  if (value === null) {
    return null;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return null;
}

function parseSummary(row: Record<string, unknown>): MyEquineSummary {
  if (
    typeof row.equine_id !== 'string' ||
    typeof row.equine_name !== 'string' ||
    !isEquineType(row.equine_type) ||
    !isStatus(row.status) ||
    !isVisibility(row.visibility_status) ||
    typeof row.is_owner !== 'boolean' ||
    typeof row.is_primary_manager !== 'boolean'
  ) {
    throw new Error(UNEXPECTED);
  }

  return {
    equineId: row.equine_id,
    equineName: row.equine_name,
    equineType: row.equine_type,
    status: row.status,
    visibilityStatus: row.visibility_status,
    isOwner: row.is_owner,
    isPrimaryManager: row.is_primary_manager,
  };
}

export function parseMyEquineSummary(value: unknown): MyEquineSummary {
  if (!isRecord(value)) {
    throw new Error(UNEXPECTED);
  }
  return parseSummary(value);
}

export function parseMyEquineDetail(value: unknown): MyEquineDetail {
  if (!isRecord(value)) {
    throw new Error(UNEXPECTED);
  }
  const summary = parseSummary(value);
  const height = value.height_cm === undefined ? null : optionalNumber(value.height_cm);
  if (value.height_cm != null && height === null) {
    throw new Error(UNEXPECTED);
  }
  if (
    value.birth_date != null &&
    typeof value.birth_date !== 'string'
  ) {
    throw new Error(UNEXPECTED);
  }

  return {
    ...summary,
    birthDate: optionalText(value.birth_date),
    sex: optionalText(value.sex),
    breed: optionalText(value.breed),
    heightCm: height,
    description: optionalText(value.description),
    temperamentDescription: optionalText(value.temperament_description),
  };
}

export function userFacingEquineCreateMessage(error: unknown): string {
  const message =
    error && typeof error === 'object' && 'message' in error
      ? String((error as { message?: unknown }).message ?? '')
      : error instanceof Error
        ? error.message
        : '';

  if (message.includes('Authentication required')) {
    return 'Inicia sesión para continuar.';
  }

  if (message.includes('Identity could not be resolved')) {
    return 'No se pudo resolver tu identidad. Completa tus datos básicos e inténtalo de nuevo.';
  }

  if (message.includes('Equine creation is not available')) {
    return 'No se puede crear el equino con la edad o el mercado de esta cuenta.';
  }

  if (message.includes('Equine name is required')) {
    return 'Escribe el nombre del equino.';
  }

  if (message.includes('Equine type is not allowed')) {
    return 'Elige caballo o poni.';
  }

  if (message.includes('Equine is not available')) {
    return 'Ese equino no está disponible para tu cuenta.';
  }

  return 'No se pudo completar la acción del equino. Inténtalo de nuevo.';
}
