export type BookableOffer = {
  centerId: string;
  centerName: string;
  centerTimezone: string | null;
  equineId: string;
  equineName: string;
  serviceId: string;
  serviceName: string;
  serviceType: string;
  startsAt: string;
  endsAt: string;
  defaultDurationMinutes: number | null;
  durationLimitMinutes: number | null;
};

export type BookingRequestResult = {
  bookingId: string;
  bookingStatus: string;
  outcome: 'CREATED' | 'REPLAYED';
};

export type BookingRequestLookup = {
  bookingId: string | null;
  bookingStatus: string | null;
  startsAt: string;
  endsAt: string;
  outcome: 'COMMITTED' | 'AMBIGUOUS';
};

export type ConfirmableBooking = {
  bookingId: string;
  equineName: string;
  centerName: string;
  serviceName: string;
  startsAt: string;
  endsAt: string;
  bookingStatus: string;
};
