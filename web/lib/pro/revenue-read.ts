/// Reads the two revenue answers **strictly** (docs/design/pro-revenue-
/// analytics.md §7, §21 « read field for field »): a body without one of
/// its parts, or with a value the contract does not list, is unreadable —
/// never a page of zeros. The app's `RevenueAnalytics.fromJson` refuses the
/// same bodies. Pure; unit-tested on the R2 server's own answers.

import {
  REVENUE_CHANNELS,
  REVENUE_COMPARES,
  REVENUE_PERIODS,
  type RevenueAnalytics,
  type RevenueFigures,
  type RevenueGroup,
  type RevenueLedgerPage,
  type RevenueLedgerRow,
  type RevenueRow,
  type RevenueRowFigures,
  type RevenueSeriesPoint,
  isRevenueDay,
} from './revenue';

type Obj = Record<string, unknown>;

class Unreadable extends Error {}

function obj(v: unknown): Obj {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) throw new Unreadable();
  return v as Obj;
}
function arr(v: unknown): unknown[] {
  if (!Array.isArray(v)) throw new Unreadable();
  return v;
}
function num(v: unknown): number {
  if (typeof v !== 'number' || !Number.isFinite(v)) throw new Unreadable();
  return v;
}
function int(v: unknown): number {
  const n = num(v);
  if (!Number.isInteger(n)) throw new Unreadable();
  return n;
}
function numOrNull(v: unknown): number | null {
  return v === null ? null : num(v);
}
function bool(v: unknown): boolean {
  if (typeof v !== 'boolean') throw new Unreadable();
  return v;
}
function str(v: unknown): string {
  if (typeof v !== 'string') throw new Unreadable();
  return v;
}
function strOrNull(v: unknown): string | null {
  return v === null ? null : str(v);
}
function day(v: unknown): string {
  const s = str(v);
  if (!isRevenueDay(s)) throw new Unreadable();
  return s;
}
function dayOrNull(v: unknown): string | null {
  return v === null ? null : day(v);
}
function instant(v: unknown): string {
  const s = str(v);
  if (Number.isNaN(Date.parse(s))) throw new Unreadable();
  return s;
}
function instantOrNull(v: unknown): string | null {
  return v === null ? null : instant(v);
}
function oneOf<T extends string>(v: unknown, values: readonly T[]): T {
  const s = str(v);
  if (!(values as readonly string[]).includes(s)) throw new Unreadable();
  return s as T;
}

const ROW_STATES = ['active', 'removed', 'unassigned', 'legacy'] as const;
const BUCKETS = ['day', 'week', 'month'] as const;
const LEDGER_STATUSES = ['completed', 'confirmed', 'noShow', 'cancelled'] as const;
const ARTIST_STATES = ['active', 'removed', 'unassigned'] as const;

function figures(v: unknown): RevenueFigures {
  const o = obj(v);
  return {
    completedAmount: num(o.completedAmount),
    completedCount: int(o.completedCount),
    averageTicket: numOrNull(o.averageTicket),
    upcomingAmount: num(o.upcomingAmount),
    upcomingCount: int(o.upcomingCount),
    pendingAmount: num(o.pendingAmount),
    pendingCount: int(o.pendingCount),
    toCloseAmount: num(o.toCloseAmount),
    toCloseCount: int(o.toCloseCount),
    noShowAmount: num(o.noShowAmount),
    noShowCount: int(o.noShowCount),
    noShowRate: numOrNull(o.noShowRate),
    cancelledAmount: num(o.cancelledAmount),
    cancelledCount: int(o.cancelledCount),
    estimated: bool(o.estimated),
  };
}

function rowFigures(v: unknown): RevenueRowFigures {
  const o = obj(v);
  return {
    completedAmount: num(o.completedAmount),
    completedCount: int(o.completedCount),
    averageTicket: numOrNull(o.averageTicket),
  };
}

function row(v: unknown): RevenueRow {
  const o = obj(v);
  return {
    key: strOrNull(o.key),
    label: strOrNull(o.label),
    state: oneOf(o.state, ROW_STATES),
    share: num(o.share),
    current: rowFigures(o.current),
    previous: o.previous === null ? null : rowFigures(o.previous),
    estimated: bool(o.estimated),
  };
}

function point(v: unknown): RevenueSeriesPoint {
  const o = obj(v);
  return {
    start: day(o.start),
    end: day(o.end),
    completedAmount: num(o.completedAmount),
    completedCount: int(o.completedCount),
  };
}

function group(v: unknown): RevenueGroup {
  const o = obj(v);
  return {
    currency: str(o.currency),
    current: figures(o.current),
    previous: o.previous === null ? null : figures(o.previous),
    series: arr(o.series).map(point),
    byArtist: arr(o.byArtist).map(row),
    byService: arr(o.byService).map(row),
    byChannel: arr(o.byChannel).map(row),
  };
}

export function readRevenueAnalytics(body: unknown): RevenueAnalytics | null {
  try {
    const o = obj(body);
    const c = obj(o.comparison);
    const f = obj(o.filters);
    return {
      period: oneOf(o.period, REVENUE_PERIODS),
      from: day(o.from),
      to: day(o.to),
      inProgress: bool(o.inProgress),
      timezone: str(o.timezone),
      asOf: instant(o.asOf),
      bucket: oneOf(o.bucket, BUCKETS),
      comparison: {
        mode: oneOf(c.mode, REVENUE_COMPARES),
        from: dayOrNull(c.from),
        to: dayOrNull(c.to),
        likeForLike: bool(c.likeForLike),
        cutoff: instantOrNull(c.cutoff),
      },
      filters: {
        artistId: strOrNull(f.artistId),
        serviceId: strOrNull(f.serviceId),
        channel: f.channel === null ? null : oneOf(f.channel, REVENUE_CHANNELS),
        label: strOrNull(f.label),
        state: f.state === null ? null : oneOf(f.state, ROW_STATES),
      },
      everCompleted: bool(o.everCompleted),
      groups: arr(o.groups).map(group),
    };
  } catch (e) {
    if (e instanceof Unreadable) return null;
    throw e;
  }
}

function ledgerRow(v: unknown): RevenueLedgerRow {
  const o = obj(v);
  const r: RevenueLedgerRow = {
    appointmentId: str(o.appointmentId),
    appointmentDate: instant(o.appointmentDate),
    status: oneOf(o.status, LEDGER_STATUSES),
    amount: num(o.amount),
    totalPrice: num(o.totalPrice),
    currency: str(o.currency),
    serviceNames: arr(o.serviceNames).map(strOrNull),
    artistLabel: strOrNull(o.artistLabel),
    artistState: oneOf(o.artistState, ARTIST_STATES),
    channel: oneOf(o.channel, REVENUE_CHANNELS),
    estimated: bool(o.estimated),
  };
  // Absent without `clients.view`, or when no client resolves (§7.2).
  if (o.clientDisplayName !== undefined) r.clientDisplayName = str(o.clientDisplayName);
  return r;
}

export function readRevenueLedger(body: unknown): RevenueLedgerPage | null {
  try {
    const o = obj(body);
    return {
      items: arr(o.items).map(ledgerRow),
      page: int(o.page),
      pageSize: int(o.pageSize),
      total: int(o.total),
      asOf: instant(o.asOf),
    };
  } catch (e) {
    if (e instanceof Unreadable) return null;
    throw e;
  }
}
