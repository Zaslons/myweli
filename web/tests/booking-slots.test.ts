import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchSlots } from '../lib/booking/client';

/// A14d — web's MISSING FOURTH STATE, and why it blocks the window work.
///
/// `fetchSlots` returned `Promise<string[]>` and did `if (!res.ok) return []`,
/// so a 500, a 502, a dead network and a genuinely quiet Saturday were the
/// same value. Both consumer surfaces then rendered « Aucun créneau
/// disponible » — telling the user the salon is full when the truth is that we
/// never reached it.
///
/// That is **the exact bug A14c fixed on mobile**, whose `SlotPicker` comment
/// still reads: *"the hub had loading / empty / success and rendered « Aucun
/// créneau disponible » for a failed request too."* Web kept it, so web has
/// three states where mobile has four — and A14d cannot give web a FIFTH
/// reason (« beyond the horizon ») before it has the fourth.
///
/// The information was always there: the BFF preserves the upstream status
/// (`app/api/availability/route.ts` returns `NextResponse.json(body, { status:
/// r.status })`). Only the client discarded it.
describe('fetchSlots — an outage is not an empty day', () => {
  afterEach(() => vi.unstubAllGlobals());

  const params = {
    providerId: 'p1',
    date: '2026-08-03',
    serviceIds: ['s1'],
    durationMinutes: 30,
  };

  it('a 500 reports failure rather than an empty list', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response('boom', { status: 500 })),
    );

    const r = await fetchSlots(params);

    expect(r.ok).toBe(false);
    expect(r.slots).toEqual([]);
  });

  it('a network throw reports failure too', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new TypeError('Failed to fetch');
      }),
    );

    const r = await fetchSlots(params);

    expect(r.ok).toBe(false);
  });

  it('a genuinely quiet day is a SUCCESS with no slots', async () => {
    // The control, and the whole distinction: without it « ok: false » could
    // be returned for everything and both assertions above would pass.
    vi.stubGlobal(
      'fetch',
      vi.fn(
        async () =>
          new Response(JSON.stringify({ slots: [] }), { status: 200 }),
      ),
    );

    const r = await fetchSlots(params);

    expect(r.ok).toBe(true);
    expect(r.slots).toEqual([]);
  });

  it('a busy day returns its slots', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(
        async () =>
          new Response(JSON.stringify({ slots: ['2026-08-03T09:00:00.000Z'] }), {
            status: 200,
          }),
      ),
    );

    const r = await fetchSlots(params);

    expect(r.ok).toBe(true);
    expect(r.slots).toEqual(['2026-08-03T09:00:00.000Z']);
  });
});
