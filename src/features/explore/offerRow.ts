import type { BookableOffer, BookingRequestLookup, BookingRequestResult, ConfirmableBooking } from './types';

function readString(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`Bookable offer is missing ${field}`);
  }
  return value;
}

function readNullableString(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value !== 'string') {
    throw new Error('Bookable offer has an unexpected text value');
  }
  return value;
}

function readNullableInt(value: unknown): number | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw new Error('Bookable offer has an unexpected duration');
  }
  return value;
}

export function parseBookableOffer(row: unknown): BookableOffer {
  if (!row || typeof row !== 'object') {
    throw new Error('Bookable offer row is empty');
  }
  const record = row as Record<string, unknown>;
  return {
    centerId: readString(record.center_id, 'center_id'),
    centerName: readString(record.center_name, 'center_name'),
    centerTimezone: readNullableString(record.center_timezone),
    equineId: readString(record.equine_id, 'equine_id'),
    equineName: readString(record.equine_name, 'equine_name'),
    serviceId: readString(record.service_id, 'service_id'),
    serviceName: readString(record.service_name, 'service_name'),
    serviceType: readString(record.service_type, 'service_type'),
    startsAt: readString(record.starts_at, 'starts_at'),
    endsAt: readString(record.ends_at, 'ends_at'),
    defaultDurationMinutes: readNullableInt(record.default_duration_minutes),
    durationLimitMinutes: readNullableInt(record.duration_limit_minutes),
  };
}

export function parseBookingRequestResult(row: unknown): BookingRequestResult {
  if (!row || typeof row !== 'object') {
    throw new Error('Booking request row is empty');
  }
  const record = row as Record<string, unknown>;
  const outcome = readString(record.outcome, 'outcome');
  if (outcome !== 'CREATED' && outcome !== 'REPLAYED') {
    throw new Error('Booking request outcome is unexpected');
  }
  return {
    bookingId: readString(record.booking_id, 'booking_id'),
    bookingStatus: readString(record.booking_status, 'booking_status'),
    outcome,
  };
}

export function parseBookingRequestLookup(row: unknown): BookingRequestLookup {
  if (!row || typeof row !== 'object') {
    throw new Error('Booking request lookup is empty');
  }
  const record = row as Record<string, unknown>;
  const outcome = readString(record.outcome, 'outcome');
  if (outcome !== 'COMMITTED' && outcome !== 'AMBIGUOUS') {
    throw new Error('Booking request lookup outcome is unexpected');
  }
  return {
    bookingId: readNullableString(record.booking_id),
    bookingStatus: readNullableString(record.booking_status),
    startsAt: readString(record.starts_at, 'starts_at'),
    endsAt: readString(record.ends_at, 'ends_at'),
    outcome,
  };
}

export function parseConfirmableBooking(row: unknown): ConfirmableBooking {
  if (!row || typeof row !== 'object') {
    throw new Error('Confirmable booking row is empty');
  }
  const record = row as Record<string, unknown>;
  return {
    bookingId: readString(record.booking_id, 'booking_id'),
    equineName: readString(record.equine_name, 'equine_name'),
    centerName: readString(record.center_name, 'center_name'),
    serviceName: readString(record.service_name, 'service_name'),
    startsAt: readString(record.starts_at, 'starts_at'),
    endsAt: readString(record.ends_at, 'ends_at'),
    bookingStatus: readString(record.booking_status, 'booking_status'),
  };
}
