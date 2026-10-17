const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

export type ExploreRange = {
  start: string;
  end: string;
};

export function initialExploreRange(now: Date): ExploreRange {
  const start = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
  return {
    start: start.toISOString(),
    end: new Date(start.getTime() + WEEK_MS).toISOString(),
  };
}

export function shiftExploreRange(range: ExploreRange, days: number): ExploreRange {
  const start = new Date(new Date(range.start).getTime() + days * 24 * 60 * 60 * 1000);
  return {
    start: start.toISOString(),
    end: new Date(start.getTime() + WEEK_MS).toISOString(),
  };
}
