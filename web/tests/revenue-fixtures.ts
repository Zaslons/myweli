import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { vi } from 'vitest';

/// « Revenus » test fixtures (docs/design/pro-revenue-analytics.md §22).
///
/// `r2(name)` is **the R2 server's own answer** — `main`'s backend run on a
/// throwaway local Postgres holding a demo salon (2026-11-27, the same files
/// as `mobile/test/support/revenue_r2/`). Nothing from production. The
/// builders below start from it, so a test's body has the contract's shape.

export function r2(name: string): Record<string, unknown> {
  return JSON.parse(
    readFileSync(join(process.cwd(), 'tests', 'revenue-r2', `${name}.json`), 'utf8'),
  ) as Record<string, unknown>;
}

type Json = Record<string, unknown>;

export function figures(over: Json = {}): Json {
  return {
    completedAmount: 0,
    completedCount: 0,
    averageTicket: null,
    upcomingAmount: 0,
    upcomingCount: 0,
    pendingAmount: 0,
    pendingCount: 0,
    toCloseAmount: 0,
    toCloseCount: 0,
    noShowAmount: 0,
    noShowCount: 0,
    noShowRate: null,
    cancelledAmount: 0,
    cancelledCount: 0,
    estimated: false,
    ...over,
  };
}

export function row(over: Json = {}): Json {
  return {
    key: 'artist_awa',
    label: 'Awa Koné',
    state: 'active',
    share: 1,
    current: { completedAmount: 50000, completedCount: 2, averageTicket: 25000 },
    previous: { completedAmount: 40000, completedCount: 2, averageTicket: 20000 },
    estimated: false,
    ...over,
  };
}

export function group(over: Json = {}): Json {
  return {
    currency: 'XOF',
    current: figures({ completedAmount: 50000, completedCount: 2, averageTicket: 25000 }),
    previous: figures({ completedAmount: 40000, completedCount: 2, averageTicket: 20000 }),
    series: [
      { start: '2026-11-01', end: '2026-11-01', completedAmount: 20000, completedCount: 1 },
      { start: '2026-11-02', end: '2026-11-02', completedAmount: 30000, completedCount: 1 },
    ],
    byArtist: [row()],
    byService: [row({ key: 'service_tresses', label: 'Tresses' })],
    byChannel: [row({ key: 'salon', label: null, state: 'active' })],
    ...over,
  };
}

/// A month answer — November 2026, in progress, compared with October like
/// for like (the R2 month answer's frame), with [over] on top.
export function analytics(over: Json = {}): Json {
  return {
    period: 'month',
    from: '2026-11-01',
    to: '2026-11-30',
    inProgress: true,
    timezone: 'Africa/Abidjan',
    asOf: '2026-11-27T09:05:53.900Z',
    bucket: 'day',
    comparison: {
      mode: 'previous',
      from: '2026-10-01',
      to: '2026-10-31',
      likeForLike: true,
      cutoff: '2026-10-27T09:05:53.900Z',
    },
    filters: { artistId: null, serviceId: null, channel: null, label: null, state: null },
    everCompleted: true,
    groups: [group()],
    ...over,
  };
}

export function ledgerRow(over: Json = {}): Json {
  return {
    appointmentId: 'appointment_1',
    appointmentDate: '2026-11-25T14:30:00.000Z',
    status: 'completed',
    amount: 35000,
    totalPrice: 35000,
    currency: 'XOF',
    clientDisplayName: 'Fatou B.',
    serviceNames: ['Tresses'],
    artistLabel: 'Awa Koné',
    artistState: 'active',
    channel: 'app',
    estimated: false,
    ...over,
  };
}

export function ledger(items: Json[], over: Json = {}): Json {
  return {
    items,
    page: 1,
    pageSize: 20,
    total: items.length,
    asOf: '2026-11-27T09:05:54.000Z',
    ...over,
  };
}

/// The signed-in owner's salon (no `membership`: the legacy owner shape,
/// every capability).
export const OWNER_PROFILE = {
  account: { id: 'acc1', businessName: 'Beauté Divine', phoneNumber: '+2250700000000' },
  provider: {
    id: 'p1',
    name: 'Beauté Divine',
    status: 'active',
    timezone: 'Africa/Abidjan',
    currency: 'XOF',
    services: [{ id: 'service_tresses', name: 'Tresses' }],
    artists: [{ id: 'artist_awa', name: 'Awa Koné' }],
  },
};

export type Answer = { status: number; body?: unknown } | 'throw' | (() => Promise<Response>);

/// A fetch double answering by path; `calls` keeps every URL asked, so a test
/// reads the query a page sent.
export function stubRevenueFetch(answers: {
  me?: Answer;
  revenue?: Answer | Answer[];
  ledger?: Answer | Answer[];
}) {
  const calls: URL[] = [];
  const queue = (a: Answer | Answer[] | undefined) => (Array.isArray(a) ? [...a] : a);
  const revenue = queue(answers.revenue);
  const ledgerAnswers = queue(answers.ledger);
  const take = (q: Answer | Answer[] | undefined): Answer | undefined =>
    Array.isArray(q) ? (q.length > 1 ? q.shift() : q[0]) : q;
  const respond = async (a: Answer | undefined): Promise<Response> => {
    if (a === undefined) return new Response('{}', { status: 404 });
    if (a === 'throw') throw new TypeError('Failed to fetch');
    if (typeof a === 'function') return a();
    return new Response(JSON.stringify(a.body ?? {}), { status: a.status });
  };
  const fetchMock = vi.fn(async (input: string) => {
    const url = new URL(String(input), 'http://localhost');
    calls.push(url);
    if (url.pathname === '/api/pro/me') {
      return respond(answers.me ?? { status: 200, body: OWNER_PROFILE });
    }
    if (url.pathname === '/api/pro/revenue') return respond(take(revenue));
    if (url.pathname === '/api/pro/revenue/appointments') return respond(take(ledgerAnswers));
    return new Response('{}', { status: 404 });
  });
  vi.stubGlobal('fetch', fetchMock);
  return {
    calls,
    /// The analytics requests' parameters, in order.
    revenueAsked: () =>
      calls.filter((u) => u.pathname === '/api/pro/revenue').map((u) => u.searchParams),
    ledgerAsked: () =>
      calls
        .filter((u) => u.pathname === '/api/pro/revenue/appointments')
        .map((u) => u.searchParams),
  };
}
