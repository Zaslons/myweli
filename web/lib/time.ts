// Design: docs/design/timezone-salon-time.md — the web salon-time seam
// (modules/multi-pays.md §3).
//
// THE RULE: storage is UTC; every displayed time and every day boundary is
// the SALON's time — never the browser's. Today the salon timezone is the
// constant below (Côte d'Ivoire = Africa/Abidjan = UTC+0, no DST). At
// multi-pays Wave 2 the constant becomes a per-salon value derived from the
// salon's city; every helper already takes the timezone as a parameter, so
// call sites won't change — only what they pass.

export const SALON_TZ = 'Africa/Abidjan';

/// Memoized Intl.DateTimeFormat factory — construction is expensive, and a
/// format must ALWAYS carry an explicit timeZone (the salon's), never the
/// device default. This is the only file allowed to construct one.
const formatterCache = new Map<string, Intl.DateTimeFormat>();

export function salonFormatter(
  options: Intl.DateTimeFormatOptions,
  tz: string = SALON_TZ,
  locale = 'fr-FR',
): Intl.DateTimeFormat {
  const key = `${locale}|${tz}|${JSON.stringify(options)}`;
  let f = formatterCache.get(key);
  if (!f) {
    f = new Intl.DateTimeFormat(locale, { ...options, timeZone: tz });
    formatterCache.set(key, f);
  }
  return f;
}

/// The salon-calendar day (`YYYY-MM-DD`) containing the instant.
/// The one legal source of day keys — never `toISOString().slice(0, 10)`.
export function salonDayKey(d: Date, tz: string = SALON_TZ): string {
  // en-CA renders numeric dates as YYYY-MM-DD.
  return salonFormatter(
    { year: 'numeric', month: '2-digit', day: '2-digit' },
    tz,
    'en-CA',
  ).format(d);
}

export function salonToday(
  now: Date = new Date(),
  tz: string = SALON_TZ,
): string {
  return salonDayKey(now, tz);
}

export function isSameSalonDay(
  a: Date,
  b: Date,
  tz: string = SALON_TZ,
): boolean {
  return salonDayKey(a, tz) === salonDayKey(b, tz);
}

/// The salon's UTC offset (minutes EAST of UTC) at the given instant —
/// computed from the timezone database, not hardcoded, so Wave 2 zones
/// (UTC+1) resolve correctly.
export function tzOffsetMinutes(d: Date, tz: string = SALON_TZ): number {
  const parts = salonFormatter(
    {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    },
    tz,
    'en-CA',
  ).formatToParts(d);
  const num = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((p) => p.type === type)?.value ?? 0);
  const wall = Date.UTC(
    num('year'),
    num('month') - 1,
    num('day'),
    num('hour'),
    num('minute'),
    num('second'),
  );
  // formatToParts carries no milliseconds — compare whole seconds.
  const instant = Math.floor(d.getTime() / 1000) * 1000;
  return Math.round((wall - instant) / 60_000);
}

/// Minutes past SALON midnight at the given instant (journal-grid geometry).
export function salonMinutesOfDay(d: Date, tz: string = SALON_TZ): number {
  const parts = salonFormatter(
    { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' },
    tz,
    'en-CA',
  ).formatToParts(d);
  const num = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((p) => p.type === type)?.value ?? 0);
  return num('hour') * 60 + num('minute');
}

/// The UTC instant of 00:00 SALON time on the salon day containing `d`.
export function salonMidnight(d: Date, tz: string = SALON_TZ): Date {
  const [y, m, day] = salonDayKey(d, tz).split('-').map(Number);
  const utcMidnight = Date.UTC(y, m - 1, day);
  return new Date(utcMidnight - tzOffsetMinutes(new Date(utcMidnight), tz) * 60_000);
}

/// The 00:00-salon-time instant `n` salon days away from `d`'s salon day.
export function addSalonDays(
  d: Date,
  n: number,
  tz: string = SALON_TZ,
): Date {
  const [y, m, day] = salonDayKey(d, tz).split('-').map(Number);
  // Noon keeps the shifted probe inside the intended day for offsets ±12 h.
  return salonMidnight(new Date(Date.UTC(y, m - 1, day + n, 12)), tz);
}

/// The UTC instant of a SALON wall-clock — `dayKey` ('YYYY-MM-DD', a salon
/// calendar day) + minutes past salon midnight. The offset-aware builder
/// behind journal drag-drops and manual-booking pickers (multi-pays MP3 —
/// retires their hardcoded-Z construction). Two-pass: guess in UTC, correct
/// by the zone offset at the guess; a DST edge converges in one re-check
/// (no DST in the launch markets — this is future-proofing).
export function salonWallClockToUtc(
  dayKey: string,
  minutes: number,
  tz: string = SALON_TZ,
): Date {
  const [y, m, d] = dayKey.split('-').map(Number);
  const guess = Date.UTC(y, m - 1, d, 0, minutes);
  const offset = tzOffsetMinutes(new Date(guess), tz);
  let instant = guess - offset * 60_000;
  const offsetAtInstant = tzOffsetMinutes(new Date(instant), tz);
  if (offsetAtInstant !== offset) instant = guess - offsetAtInstant * 60_000;
  return new Date(instant);
}

export type SalonPeriod = 'today' | 'week' | 'month' | 'all';

/// Inclusive-start/exclusive-end ISO range for a period, computed on SALON
/// day boundaries (Monday-start week, calendar month), or null for all time.
/// Replaces the device-local math that made « Aujourd'hui » buckets drift on
/// non-UTC devices.
export function salonDayRange(
  key: SalonPeriod,
  now: Date = new Date(),
  tz: string = SALON_TZ,
): { startDate: string; endDate: string } | null {
  if (key === 'all') return null;
  const dayStart = salonMidnight(now, tz);
  if (key === 'today') {
    return {
      startDate: dayStart.toISOString(),
      endDate: addSalonDays(dayStart, 1, tz).toISOString(),
    };
  }
  if (key === 'week') {
    const [y, m, day] = salonDayKey(now, tz).split('-').map(Number);
    const weekday = new Date(Date.UTC(y, m - 1, day)).getUTCDay(); // 0 = Sunday
    const start = addSalonDays(dayStart, -((weekday + 6) % 7), tz);
    return {
      startDate: start.toISOString(),
      endDate: addSalonDays(start, 7, tz).toISOString(),
    };
  }
  const [y, m] = salonDayKey(now, tz).split('-').map(Number);
  const start = salonMidnight(new Date(Date.UTC(y, m - 1, 1, 12)), tz);
  const end = salonMidnight(new Date(Date.UTC(y, m, 1, 12)), tz);
  return { startDate: start.toISOString(), endDate: end.toISOString() };
}

/// Whether the viewer's device clock disagrees with the salon's at `at` —
/// drives the « Heures affichées : heure du salon » hint. `deviceOffsetMin`
/// is minutes EAST of UTC (JS's getTimezoneOffset() is inverted — west-
/// positive — so the default negates it).
export function salonOffsetDiffers(
  at: Date = new Date(),
  tz: string = SALON_TZ,
  deviceOffsetMin: number = -at.getTimezoneOffset(),
): boolean {
  return deviceOffsetMin !== tzOffsetMinutes(at, tz);
}
