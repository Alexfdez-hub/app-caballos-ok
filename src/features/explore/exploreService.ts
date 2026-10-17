import { supabase } from '../../services/supabase/client';
import {
  parseBookableOffer,
  parseBookingRequestLookup,
  parseBookingRequestResult,
  parseConfirmableBooking,
} from './offerRow';
import type {
  BookableOffer,
  BookingRequestLookup,
  BookingRequestResult,
  ConfirmableBooking,
} from './types';

export async function listBookableOffers(
  rangeStart: string,
  rangeEnd: string,
): Promise<BookableOffer[]> {
  const { data, error } = await supabase.rpc('list_bookable_offers', {
    p_range_start: rangeStart,
    p_range_end: rangeEnd,
  });

  if (error) {
    throw error;
  }

  return ((data ?? []) as unknown[]).map((row) => parseBookableOffer(row));
}

export async function getBookableOffer(input: {
  equineId: string;
  centerId: string;
  serviceId: string;
  startsAt: string;
  endsAt: string;
}): Promise<BookableOffer | null> {
  const { data, error } = await supabase.rpc('get_bookable_offer', {
    p_equine_id: input.equineId,
    p_center_id: input.centerId,
    p_service_id: input.serviceId,
    p_starts_at: input.startsAt,
    p_ends_at: input.endsAt,
  });

  if (error) {
    throw error;
  }

  const rows = ((data ?? []) as unknown[]).map((row) => parseBookableOffer(row));
  return rows[0] ?? null;
}

export async function requestBookableSlot(input: {
  clientRequestId: string;
  equineId: string;
  centerId: string;
  serviceId: string;
  startsAt: string;
  endsAt: string;
}): Promise<BookingRequestResult> {
  const { data, error } = await supabase.rpc('request_bookable_slot', {
    p_client_request_id: input.clientRequestId,
    p_equine_id: input.equineId,
    p_center_id: input.centerId,
    p_service_id: input.serviceId,
    p_starts_at: input.startsAt,
    p_ends_at: input.endsAt,
  });

  if (error) {
    throw error;
  }

  const rows = ((data ?? []) as unknown[]).map((row) => parseBookingRequestResult(row));
  const row = rows[0];
  if (!row) {
    throw new Error('Booking request returned no row');
  }
  return row;
}

export async function getMyBookingRequest(
  clientRequestId: string,
): Promise<BookingRequestLookup | null> {
  const { data, error } = await supabase.rpc('get_my_booking_request', {
    p_client_request_id: clientRequestId,
  });

  if (error) {
    throw error;
  }

  const rows = ((data ?? []) as unknown[]).map((row) => parseBookingRequestLookup(row));
  return rows[0] ?? null;
}

export async function listBookingsICanConfirm(): Promise<ConfirmableBooking[]> {
  const { data, error } = await supabase.rpc('list_bookings_i_can_confirm');

  if (error) {
    throw error;
  }

  return ((data ?? []) as unknown[]).map((row) => parseConfirmableBooking(row));
}

export async function confirmBooking(bookingId: string): Promise<string> {
  const { data, error } = await supabase.rpc('confirm_booking', {
    p_booking_id: bookingId,
  });

  if (error) {
    throw error;
  }

  if (typeof data !== 'string' || data.length === 0) {
    throw new Error('Confirm returned an unexpected result.');
  }

  return data;
}

export async function startBookedSession(bookingId: string): Promise<string> {
  const { data, error } = await supabase.rpc('start_session', {
    p_booking_id: bookingId,
  });

  if (error) {
    throw error;
  }

  if (typeof data !== 'string' || data.length === 0) {
    throw new Error('Start session returned an unexpected result.');
  }

  return data;
}

export async function endBookedSession(sessionId: string): Promise<string> {
  const { data, error } = await supabase.rpc('end_session', {
    p_session_id: sessionId,
  });

  if (error) {
    throw error;
  }

  if (typeof data !== 'string' || data.length === 0) {
    throw new Error('End session returned an unexpected result.');
  }

  return data;
}
