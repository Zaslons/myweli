/// « Revenus » on the website — the query, its address, and the period bar's
/// calendar (docs/design/pro-revenue-analytics.md §3.5, §5.2, §22). Pure, so
/// every rule has a unit test; the app's twin is
/// `mobile/lib/core/utils/revenue_periods.dart` + `RevenueQuery`.
///
/// **The server owns the calendar.** The page never resolves a week or a
/// month: it sends `period` and a `date` (or nothing — the salon's today, as
/// the server reads it), and steps ‹ › from the answer's own `from`/`to` —
/// date arithmetic on dates, no clock involved. The one « today » it needs
/// (how far › may go) is the answer's `asOf` read in the salon's zone.

import type { components } from '../api/schema';
import { dayKeyOf, formatDayKey, salonDayKey, salonFormatter, shiftDayKey } from '../time';

export type RevenueAnalytics = components['schemas']['RevenueAnalytics'];
export type RevenueGroup = components['schemas']['RevenueGroup'];
export type RevenueFigures = components['schemas']['RevenueFigures'];
export type RevenueRow = components['schemas']['RevenueRow'];
export type RevenueRowFigures = components['schemas']['RevenueRowFigures'];
export type RevenueSeriesPoint = components['schemas']['RevenueSeriesPoint'];
export type RevenueFilters = components['schemas']['RevenueFilters'];
export type RevenueLedgerPage = components['schemas']['RevenueLedgerPage'];
export type RevenueLedgerRow = components['schemas']['RevenueLedgerRow'];

export type RevenuePeriod = RevenueAnalytics['period'];
export type RevenueCompare = RevenueAnalytics['comparison']['mode'];
export type RevenueBucket = RevenueAnalytics['bucket'];
export type RevenueRowState = RevenueRow['state'];
export type RevenueChannel = RevenueLedgerRow['channel'];
export type RevenueAxis = 'artist' | 'service' | 'channel';
export type RevenueSort = 'amount' | 'count' | 'name';
export type RevenueLedgerStatus =
  | 'completed'
  | 'upcoming'
  | 'toClose'
  | 'noShow'
  | 'cancelled';

export const REVENUE_PERIODS: readonly RevenuePeriod[] = [
  'day',
  'week',
  'month',
  'year',
  'custom',
];
export const REVENUE_COMPARES: readonly RevenueCompare[] = [
  'previous',
  'year',
  'none',
];
export const REVENUE_AXES: readonly RevenueAxis[] = [
  'artist',
  'service',
  'channel',
];
export const REVENUE_CHANNELS: readonly RevenueChannel[] = [
  'app',
  'web',
  'salon',
  'online',
];
export const REVENUE_LEDGER_STATUSES: readonly RevenueLedgerStatus[] = [
  'completed',
  'upcoming',
  'toClose',
  'noShow',
  'cancelled',
];

/// The server's reserved key for « Sans collaborateur attribué » (§7.1).
export const NO_ARTIST = 'none';

/// The server's bounds (§3.5): no date before 2020, none past the salon's
/// today + 366 days, no range longer than 366 days.
export const REVENUE_EARLIEST_DAY = '2020-01-01';
export const REVENUE_MAX_DAYS = 366;

/// Ids as the server accepts them (§7.1).
const ID = /^[A-Za-z0-9_-]{1,64}$/;

export function isRevenueId(v: string | null | undefined): v is string {
  return typeof v === 'string' && ID.test(v);
}

// ── Days (« AAAA-MM-JJ », salon dates — never instants) ─────────────────────

const DAY = /^(\d{4})-(\d{2})-(\d{2})$/;
const MS_PER_DAY = 86_400_000;

function utc(day: string): number {
  return Date.parse(`${day}T00:00:00.000Z`);
}

/// A real calendar day in the server's form — « 2026-02-30 » is not one.
export function isRevenueDay(v: string | null | undefined): v is string {
  if (typeof v !== 'string') return false;
  const m = DAY.exec(v);
  if (!m) return false;
  return dayKeyOf(Number(m[1]), Number(m[2]), Number(m[3])) === v;
}

/// The day [n] days after [day] (before, for a negative [n]).
export function addRevenueDays(day: string, n: number): string {
  return shiftDayKey(day, n);
}

/// Whole days from [from] to [to] (0 for the same day).
export function revenueDaysBetween(from: string, to: string): number {
  return Math.round((utc(to) - utc(from)) / MS_PER_DAY);
}

/// A day from its parts; an overflowing month or day rolls over, as the
/// calendar does (month 0 is December of the year before).
export function revenueDay(year: number, month: number, day: number): string {
  return dayKeyOf(year, month, day);
}

export function dayParts(day: string): { y: number; m: number; d: number } {
  const [y, m, d] = day.split('-').map(Number);
  return { y, m, d };
}

/// 1 = Monday … 7 = Sunday.
export function revenueWeekday(day: string): number {
  return ((new Date(utc(day)).getUTCDay() + 6) % 7) + 1;
}

// ── The query ────────────────────────────────────────────────────────────────

/// What the page asks the server (§7.1): a period, its comparison, and the
/// filters of a detail.
export type RevenueQuery = {
  period: RevenuePeriod;
  /// Any day inside the period; null = the salon's today, as the server
  /// reads it. Never with `custom`.
  date: string | null;
  /// `custom` only.
  from: string | null;
  to: string | null;
  compare: RevenueCompare;
  artistId: string | null;
  serviceId: string | null;
  channel: RevenueChannel | null;
};

export function revenueQuery(partial: Partial<RevenueQuery> = {}): RevenueQuery {
  return {
    period: 'month',
    date: null,
    from: null,
    to: null,
    compare: 'previous',
    artistId: null,
    serviceId: null,
    channel: null,
    ...partial,
  };
}

/// [q] on another period, its filters and comparison kept.
export function withPeriod(
  q: RevenueQuery,
  period: RevenuePeriod,
  dates: { date?: string | null; from?: string; to?: string } = {},
): RevenueQuery {
  return period === 'custom'
    ? { ...q, period, date: null, from: dates.from ?? null, to: dates.to ?? null }
    : { ...q, period, date: dates.date ?? null, from: null, to: null };
}

export function sameRevenueQuery(a: RevenueQuery, b: RevenueQuery): boolean {
  return (
    a.period === b.period &&
    a.date === b.date &&
    a.from === b.from &&
    a.to === b.to &&
    a.compare === b.compare &&
    a.artistId === b.artistId &&
    a.serviceId === b.serviceId &&
    a.channel === b.channel
  );
}

/// The query string the BFF forwards to `GET …/analytics/revenue` (§7.1).
export function revenueApiParams(q: RevenueQuery): URLSearchParams {
  const p = new URLSearchParams();
  p.set('period', q.period);
  if (q.period === 'custom') {
    if (q.from) p.set('from', q.from);
    if (q.to) p.set('to', q.to);
  } else if (q.date) {
    p.set('date', q.date);
  }
  p.set('compare', q.compare);
  if (q.artistId) p.set('artistId', q.artistId);
  if (q.serviceId) p.set('serviceId', q.serviceId);
  if (q.channel) p.set('channel', q.channel);
  return p;
}

// ── The address (§5.2) — French words without accents, as the agenda's ─────

const PERIOD_SLUG: Record<RevenuePeriod, string> = {
  day: 'jour',
  week: 'semaine',
  month: 'mois',
  year: 'annee',
  custom: 'dates',
};
const COMPARE_SLUG: Record<RevenueCompare, string> = {
  previous: 'precedente',
  year: 'annee',
  none: 'aucune',
};
const AXIS_SLUG: Record<RevenueAxis, string> = {
  artist: 'collaborateurs',
  service: 'prestations',
  channel: 'canaux',
};
const SORT_SLUG: Record<RevenueSort, string> = {
  amount: 'montant',
  count: 'rendez-vous',
  name: 'nom',
};
export const CHANNEL_SLUG: Record<RevenueChannel, string> = {
  app: 'application',
  web: 'site',
  salon: 'salon',
  online: 'en-ligne',
};
const STATUS_SLUG: Record<RevenueLedgerStatus, string> = {
  completed: 'termines',
  upcoming: 'a-venir',
  toClose: 'a-cloturer',
  noShow: 'absents',
  cancelled: 'annules',
};

/// Maps, not object lookups: an address is anyone's input, and a plain
/// object answers `toString` or `__proto__` through its prototype.
function reverse<T extends string>(m: Record<T, string>): Map<string, T> {
  return new Map(Object.entries(m).map(([k, v]) => [v as string, k as T]));
}
const PERIOD_OF = reverse(PERIOD_SLUG);
const COMPARE_OF = reverse(COMPARE_SLUG);
const AXIS_OF = reverse(AXIS_SLUG);
const SORT_OF = reverse(SORT_SLUG);
const CHANNEL_OF = reverse(CHANNEL_SLUG);
const STATUS_OF = reverse(STATUS_SLUG);

/// A channel from its address word (`/pro/revenus/canaux/[canal]`).
export function channelFromSlug(slug: string | null | undefined): RevenueChannel | null {
  return slug == null ? null : (CHANNEL_OF.get(slug) ?? null);
}

/// Everything an address can say. The path says the detail's own filter;
/// the query says the rest.
export type RevenueAddress = {
  period: RevenuePeriod;
  date: string | null;
  from: string | null;
  to: string | null;
  /// Null when the address does not say: the session's choice applies.
  compare: RevenueCompare | null;
  /// « Répartition »'s tab; null = the first one the page has.
  tab: RevenueAxis | null;
  sort: RevenueSort;
  /// A second filter (a detail inside a detail, §5.4) or a ledger's filters.
  artistId: string | null;
  serviceId: string | null;
  channel: RevenueChannel | null;
  /// The ledger only.
  status: RevenueLedgerStatus;
  asOf: string | null;
  /// The salon a detail or a ledger belongs to.
  salon: string | null;
};

const DEFAULT_ADDRESS: RevenueAddress = {
  period: 'month',
  date: null,
  from: null,
  to: null,
  compare: null,
  tab: null,
  sort: 'amount',
  artistId: null,
  serviceId: null,
  channel: null,
  status: 'completed',
  asOf: null,
  salon: null,
};

/// Reads an address. **A malformed period falls back to the current month,
/// without an error page** (§5.2): an unknown word, a date that is not a
/// day, a date out of the server's bounds, a range backwards or too long.
/// [today] is the salon's today by the device's clock — only to refuse a
/// date the server would (past today + 366 days).
export function readRevenueAddress(
  search: string | URLSearchParams,
  today: string,
): RevenueAddress {
  const p = typeof search === 'string' ? new URLSearchParams(search) : search;
  const a: RevenueAddress = { ...DEFAULT_ADDRESS };
  const latest = addRevenueDays(today, REVENUE_MAX_DAYS);
  const inBounds = (d: string) => d >= REVENUE_EARLIEST_DAY && d <= latest;

  const periode = p.get('periode');
  const period = periode == null ? 'month' : PERIOD_OF.get(periode);
  if (period === 'custom') {
    const from = p.get('du');
    const to = p.get('au');
    if (
      isRevenueDay(from) &&
      isRevenueDay(to) &&
      inBounds(from) &&
      inBounds(to) &&
      customRangeError(from, to) == null
    ) {
      a.period = 'custom';
      a.from = from;
      a.to = to;
    }
  } else if (period) {
    const date = p.get('date');
    if (date == null) {
      a.period = period;
    } else if (isRevenueDay(date) && inBounds(date)) {
      a.period = period;
      a.date = date;
    }
  }

  a.compare = COMPARE_OF.get(p.get('comparer') ?? '') ?? null;
  a.tab = AXIS_OF.get(p.get('vue') ?? '') ?? null;
  a.sort = SORT_OF.get(p.get('tri') ?? '') ?? 'amount';
  const artist = p.get('collaborateur');
  a.artistId = isRevenueId(artist) ? artist : null;
  const service = p.get('prestation');
  a.serviceId = isRevenueId(service) ? service : null;
  a.channel = channelFromSlug(p.get('canal'));
  a.status = STATUS_OF.get(p.get('statut') ?? '') ?? 'completed';
  const asOf = p.get('instant');
  a.asOf = asOf != null && !Number.isNaN(Date.parse(asOf)) ? asOf : null;
  const salon = p.get('salon');
  a.salon = isRevenueId(salon) ? salon : null;
  return a;
}

/// Writes an address: `?…`, or '' when everything is the default. The
/// defaults — « Mois », the salon's today, « Période précédente », the first
/// tab, « Montant », « Terminés » — are never written, so a bare
/// `/pro/revenus` stays « now ». The order is fixed, so one state has one
/// address.
export function revenueSearch(a: Partial<RevenueAddress>): string {
  const p = new URLSearchParams();
  const period = a.period ?? 'month';
  if (period !== 'month') p.set('periode', PERIOD_SLUG[period]);
  if (period === 'custom') {
    if (a.from) p.set('du', a.from);
    if (a.to) p.set('au', a.to);
  } else if (a.date) {
    p.set('date', a.date);
  }
  if (a.compare && a.compare !== 'previous') p.set('comparer', COMPARE_SLUG[a.compare]);
  if (a.tab) p.set('vue', AXIS_SLUG[a.tab]);
  if (a.sort && a.sort !== 'amount') p.set('tri', SORT_SLUG[a.sort]);
  if (a.artistId) p.set('collaborateur', a.artistId);
  if (a.serviceId) p.set('prestation', a.serviceId);
  if (a.channel) p.set('canal', CHANNEL_SLUG[a.channel]);
  if (a.status && a.status !== 'completed') p.set('statut', STATUS_SLUG[a.status]);
  if (a.asOf) p.set('instant', a.asOf);
  if (a.salon) p.set('salon', a.salon);
  const s = p.toString();
  return s ? `?${s}` : '';
}

/// The period part of [q], as an address carries it.
export function periodAddress(q: RevenueQuery): Partial<RevenueAddress> {
  return {
    period: q.period,
    date: q.date,
    from: q.from,
    to: q.to,
    compare: q.compare,
  };
}

/// The overview (§5.2), on [q]'s period.
export function revenueOverviewHref(q: RevenueQuery): string {
  return `/pro/revenus${revenueSearch(periodAddress(q))}`;
}

/// A row's detail: `/pro/revenus/collaborateurs/[id]` ·
/// `/prestations/[id]` · `/canaux/[canal]`, the period in the query. From a
/// detail, the detail's own filter goes in the query too — a detail inside
/// a detail (§5.4). [salon] ties the page to its salon.
export function revenueDetailHref(
  axis: RevenueAxis,
  key: string | null,
  q: RevenueQuery,
  salon: string,
  tab?: RevenueAxis | null,
): string {
  const base = periodAddress(q);
  const extra: Partial<RevenueAddress> = { salon, tab: tab ?? null };
  let path: string;
  switch (axis) {
    case 'artist':
      path = `/pro/revenus/collaborateurs/${encodeURIComponent(key ?? NO_ARTIST)}`;
      extra.serviceId = q.serviceId;
      extra.channel = q.channel;
      break;
    case 'service':
      path = `/pro/revenus/prestations/${encodeURIComponent(key ?? '')}`;
      extra.artistId = q.artistId;
      extra.channel = q.channel;
      break;
    case 'channel': {
      const channel = channelFromApi(key);
      path = `/pro/revenus/canaux/${channel ? CHANNEL_SLUG[channel] : ''}`;
      extra.artistId = q.artistId;
      extra.serviceId = q.serviceId;
      break;
    }
  }
  return `${path}${revenueSearch({ ...base, ...extra })}`;
}

/// The ledger (§4.9): the period, every filter, the status, and the
/// figures' `asOf` — so « À clôturer » lists what the banner counted.
export function revenueLedgerHref(
  q: RevenueQuery,
  status: RevenueLedgerStatus,
  salon: string,
  asOf?: string | null,
): string {
  return `/pro/revenus/rendez-vous${revenueSearch({
    ...periodAddress(q),
    artistId: q.artistId,
    serviceId: q.serviceId,
    channel: q.channel,
    status,
    asOf: asOf ?? null,
    salon,
  })}`;
}

/// A channel as the server writes it, or null.
export function channelFromApi(v: string | null | undefined): RevenueChannel | null {
  return (REVENUE_CHANNELS as readonly string[]).includes(v ?? '')
    ? (v as RevenueChannel)
    : null;
}

// ── The calendar (§3.5, §4.3), stepped from the answer ──────────────────────

/// The salon's today, as the answer measured it.
export function revenueToday(a: RevenueAnalytics): string {
  return salonDayKey(new Date(a.asOf), a.timezone);
}

/// The last day the server accepts: the salon's today + 366 days.
export function revenueLatestDay(a: RevenueAnalytics): string {
  return addRevenueDays(revenueToday(a), REVENUE_MAX_DAYS);
}

/// Days in [a]'s range, both ends counted.
export function revenueRangeDays(a: { from: string; to: string }): number {
  return revenueDaysBetween(a.from, a.to) + 1;
}

/// The period before [a]'s, as a query — or null at 2020 (« ‹ stops at
/// 2020 »). A period that straddles 1 January 2020 is asked by its first
/// valid day (§20.1 item 1).
export function previousRevenuePeriod(
  a: RevenueAnalytics,
  q: RevenueQuery,
): RevenueQuery | null {
  let from: string;
  let to: string;
  switch (a.period) {
    case 'day':
      from = addRevenueDays(a.from, -1);
      to = from;
      break;
    case 'week':
      from = addRevenueDays(a.from, -7);
      to = addRevenueDays(a.from, -1);
      break;
    case 'month': {
      const { y, m } = dayParts(a.from);
      from = revenueDay(y, m - 1, 1);
      to = addRevenueDays(a.from, -1);
      break;
    }
    case 'year':
      from = revenueDay(dayParts(a.from).y - 1, 1, 1);
      to = addRevenueDays(a.from, -1);
      break;
    case 'custom': {
      // « custom ranges step by their own length »; both ends must be valid.
      const start = addRevenueDays(a.from, -revenueRangeDays(a));
      if (start < REVENUE_EARLIEST_DAY) return null;
      return withPeriod(q, 'custom', { from: start, to: addRevenueDays(a.from, -1) });
    }
  }
  if (to < REVENUE_EARLIEST_DAY) return null;
  return withPeriod(q, a.period, {
    date: from < REVENUE_EARLIEST_DAY ? REVENUE_EARLIEST_DAY : from,
  });
}

/// The period after [a]'s — or null past the salon's today + 366 days.
export function nextRevenuePeriod(
  a: RevenueAnalytics,
  q: RevenueQuery,
): RevenueQuery | null {
  const latest = revenueLatestDay(a);
  const next = addRevenueDays(a.to, 1);
  if (a.period === 'custom') {
    const to = addRevenueDays(a.to, revenueRangeDays(a));
    if (to > latest) return null;
    return withPeriod(q, 'custom', { from: next, to });
  }
  if (next > latest) return null;
  return withPeriod(q, a.period, { date: next });
}

/// Another kind of period, keeping the anchor (§4.3): « now » when [a]
/// contains today (no date — the server's today), else [a]'s first day.
export function switchRevenuePeriod(
  a: RevenueAnalytics | null,
  q: RevenueQuery,
  period: Exclude<RevenuePeriod, 'custom'>,
): RevenueQuery {
  const anchor = a == null || a.inProgress ? null : a.from;
  return withPeriod(q, period, { date: anchor });
}

/// Why a « Dates… » range is refused — the error under « Au » (§4.3), or
/// null when it can be asked.
export function customRangeError(from: string, to: string): string | null {
  if (to < from) return 'La date de fin précède la date de début';
  if (revenueDaysBetween(from, to) + 1 > REVENUE_MAX_DAYS) return '366 jours au plus';
  return null;
}

/// The period has days today or later — « Prévu » is shown (§4.5).
export function revenueHasFuture(a: RevenueAnalytics): boolean {
  return a.to >= revenueToday(a);
}

/// The period has not begun (§4.11 « A future period »).
export function revenueIsFuture(a: RevenueAnalytics): boolean {
  return a.from > revenueToday(a);
}

// ── Words for days (the app's Formatters, on salon dates) ───────────────────

/// The day is a salon date already (the server resolved it): named as a
/// calendar date, through the time seam.
function part(day: string, options: Intl.DateTimeFormatOptions): string {
  return formatDayKey(day, options);
}

/// « 1er » · « 25 » — French writes the first of the month as an ordinal.
function dayOrdinal(day: string): string {
  const d = dayParts(day).d;
  return d === 1 ? '1er' : String(d);
}

export function capitalized(text: string): string {
  return text ? text[0].toUpperCase() + text.slice(1) : text;
}

/// « 1er nov. »
export function formatDayMonthShort(day: string): string {
  return `${dayOrdinal(day)} ${part(day, { month: 'short' })}`;
}

/// « mar. 4 nov. » — the chart's selected day.
export function formatWeekdayDayMonthShort(day: string): string {
  return `${part(day, { weekday: 'short' })} ${formatDayMonthShort(day)}`;
}

/// « Mardi 25 novembre » — a « Jour » title; the year when it is not
/// [currentYear] (« Lundi 24 novembre 2025 »).
export function formatPeriodDay(day: string, currentYear: number): string {
  const { y } = dayParts(day);
  return capitalized(
    `${part(day, { weekday: 'long' })} ${dayOrdinal(day)} ${part(day, { month: 'long' })}` +
      (y === currentYear ? '' : ` ${y}`),
  );
}

/// « novembre 2026 »
export function formatMonthYear(day: string): string {
  return `${part(day, { month: 'long' })} ${dayParts(day).y}`;
}

/// « nov. » — a month bucket under the chart.
export function formatMonthShort(day: string): string {
  return part(day, { month: 'short' });
}

/// A range of days, the year said once at the end: « 25 nov. 2026 » ·
/// « 24 – 30 nov. 2026 » · « 3 oct. – 25 nov. 2026 » ·
/// « 29 déc. 2025 – 4 janv. 2026 ».
export function formatDayRange(from: string, to: string): string {
  const f = dayParts(from);
  const t = dayParts(to);
  if (from === to) return `${formatDayMonthShort(to)} ${t.y}`;
  if (f.y !== t.y) {
    return `${formatDayMonthShort(from)} ${f.y} – ${formatDayMonthShort(to)} ${t.y}`;
  }
  const start = f.m === t.m ? dayOrdinal(from) : formatDayMonthShort(from);
  return `${start} – ${formatDayMonthShort(to)} ${t.y}`;
}

/// The period's title (§4.3): « Mardi 25 novembre » · « 24 – 30 nov. 2026 »
/// · « Novembre 2026 » · « 2026 » · « 3 oct. – 25 nov. 2026 ».
export function revenuePeriodTitle(a: RevenueAnalytics): string {
  switch (a.period) {
    case 'day':
      return formatPeriodDay(a.from, dayParts(revenueToday(a)).y);
    case 'month':
      return capitalized(formatMonthYear(a.from));
    case 'year':
      return String(dayParts(a.from).y);
    case 'week':
    case 'custom':
      return formatDayRange(a.from, a.to);
  }
}

/// The title of [q] before its answer lands, so the bar changes at once
/// (§4.11 « Period change ») — the same words, from the query's own dates.
/// [today] is the salon's today (from the last answer, or the device's clock
/// before the first, §21.1 item 14); the answer's dates replace it.
export function provisionalRevenueTitle(q: RevenueQuery, today: string | null): string | null {
  if (q.period === 'custom') {
    return q.from && q.to ? formatDayRange(q.from, q.to) : null;
  }
  const d = q.date ?? today;
  if (d == null) return null;
  switch (q.period) {
    case 'day':
      return formatPeriodDay(d, dayParts(today ?? d).y);
    case 'week': {
      const monday = addRevenueDays(d, -(revenueWeekday(d) - 1));
      return formatDayRange(monday, addRevenueDays(monday, 6));
    }
    case 'month': {
      const { y, m } = dayParts(d);
      return capitalized(formatMonthYear(revenueDay(y, m, 1)));
    }
    case 'year':
      return String(dayParts(d).y);
  }
}

/// What the period is compared with, in words — « octobre 2026 »,
/// « 1er – 25 oct. 2026, même avancement », « 2025 » — or null with
/// « Aucune comparaison » (§21.1 item 9).
export function revenueComparisonLabel(a: RevenueAnalytics): string | null {
  const c = a.comparison;
  const { from, to } = c;
  if (c.mode === 'none' || from == null || to == null) return null;
  if (c.likeForLike && c.cutoff != null) {
    // The last day the cut reaches: the day of the instant just before it
    // (a cut clipped to its period's end is midnight after `to`).
    const last = salonDayKey(new Date(Date.parse(c.cutoff) - 1), a.timezone);
    const end = last < from ? from : last > to ? to : last;
    return `${formatDayRange(from, end)}, même avancement`;
  }
  const f = dayParts(from);
  const t = dayParts(to);
  const wholeMonth = f.d === 1 && dayParts(addRevenueDays(to, 1)).d === 1 && f.m === t.m && f.y === t.y;
  if (wholeMonth) return formatMonthYear(from);
  const wholeYear = f.m === 1 && f.d === 1 && t.m === 12 && t.d === 31 && f.y === t.y;
  if (wholeYear) return String(f.y);
  return formatDayRange(from, to);
}

/// « mar. 25 nov. · 14:30 » — a booking's start, in the salon's time (§4.9).
export function formatLedgerWhen(iso: string, timezone: string): string {
  const at = new Date(iso);
  const time = salonFormatter({ hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }, timezone).format(at);
  return `${formatWeekdayDayMonthShort(salonDayKey(at, timezone))} · ${time}`;
}
