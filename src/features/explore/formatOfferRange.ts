function pad(value: number): string {
  return String(value).padStart(2, '0');
}

export function formatOfferRange(
  startsAt: string,
  endsAt: string,
  timeZone: string | null,
): string {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  const zone = usableTimeZone(timeZone);
  const startParts = zonedParts(start, zone);
  const endParts = zonedParts(end, zone);
  return `${startParts.date} ${startParts.time}–${endParts.time} ${zone}`;
}

function usableTimeZone(timeZone: string | null): string {
  if (!timeZone) {
    return 'UTC';
  }

  try {
    Intl.DateTimeFormat('en-US', { timeZone }).format(new Date());
    return timeZone;
  } catch {
    return 'UTC';
  }
}

function zonedParts(value: Date, timeZone: string): { date: string; time: string } {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(value);
  const read = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? '';
  return {
    date: `${read('year')}-${read('month')}-${read('day')}`,
    time: `${pad(Number(read('hour')))}:${pad(Number(read('minute')))}`,
  };
}
