import { afterEach, describe, expect, it, vi } from 'vitest';

import * as account from '../lib/api/account';
import * as pro from '../lib/api/pro';
import { fetchSlots } from '../lib/booking/client';

/// docs/design/hygiene-batch9.md §2.10 (B9.11) — a list read requires its
/// list. The server always sends it, so a 200 without one is a failed read
/// (status 0, the page's error state with its retry), never « nothing here ».
/// #630 made the export's reads strict this way; these eight still turned a
/// readable 200 with no list into `[]` — a salon told it has no team, no
/// reviews, no invitations, and a client search that would crash on `{}`.
/// A real empty list stays a real empty list.

function answer(body: string, status = 200) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(body, { status })),
  );
}

afterEach(() => vi.unstubAllGlobals());

type Read = {
  name: string;
  call: () => Promise<{ status: number }>;
  /// The list the response carries, and what the result names it.
  key: string;
  resultKey?: string;
};

const READS: Read[] = [
  { name: 'account.getNotifications', call: () => account.getNotifications(), key: 'items' },
  { name: 'pro.getProNotifications', call: () => pro.getProNotifications(), key: 'items' },
  { name: 'pro.getMySalons', call: () => pro.getMySalons(), key: 'items' },
  { name: 'pro.listProviderReviews', call: () => pro.listProviderReviews('p1'), key: 'items' },
  { name: 'pro.getTeamMembers', call: () => pro.getTeamMembers(), key: 'items' },
  { name: 'pro.getMyInvitations', call: () => pro.getMyInvitations(), key: 'invitations' },
  { name: 'pro.getClientVisits', call: () => pro.getClientVisits('p1', 'c1'), key: 'items' },
  {
    name: 'pro.listClients',
    call: () => pro.listClients('p1'),
    key: 'items',
    resultKey: 'list',
  },
];

describe('a 200 without its list is a failed read', () => {
  for (const r of READS) {
    it(`${r.name}: \`{}\` is status 0`, async () => {
      answer('{}');
      expect((await r.call()).status).toBe(0);
    });

    it(`${r.name}: a \`${r.key}\` that is not a list is status 0`, async () => {
      answer(JSON.stringify({ [r.key]: 'x', total: 1, page: 1, pageSize: 20 }));
      expect((await r.call()).status).toBe(0);
    });

    it(`${r.name}: a real empty list is a real empty list`, async () => {
      answer(JSON.stringify({ [r.key]: [], total: 0, page: 1, pageSize: 20 }));
      const res = (await r.call()) as Record<string, unknown>;
      expect(res.status).toBe(200);
      const list = r.resultKey
        ? (res[r.resultKey] as Record<string, unknown>)[r.key]
        : res[r.key];
      expect(list).toEqual([]);
    });
  }

  it('fetchSlots: `{}` is « we could not ask », not an empty day', async () => {
    answer('{}');
    expect(
      await fetchSlots({
        providerId: 'p1',
        date: '2026-08-03',
        serviceIds: ['s1'],
        durationMinutes: 30,
      }),
    ).toEqual({ ok: false, slots: [] });
  });

  it('fetchSlots: a real empty day is an empty day', async () => {
    answer(JSON.stringify({ slots: [] }));
    expect(
      await fetchSlots({
        providerId: 'p1',
        date: '2026-08-03',
        serviceIds: ['s1'],
        durationMinutes: 30,
      }),
    ).toEqual({ ok: true, slots: [] });
  });
});
