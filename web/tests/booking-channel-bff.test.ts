// @vitest-environment node
import { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { POST as cancelBooking } from '../app/api/appointments/[id]/cancel/route';
import { POST as book } from '../app/api/bookings/route';
import { POST as bookForClient } from '../app/api/pro/appointments/route';

/// docs/design/pro-revenue-analytics.md §8.2 (R0w, decision 243): a booking
/// made on the website tells the API so, with `X-Myweli-Channel: web`, and the
/// API stamps it `web` (from R1; until then it ignores the header). The app
/// sends nothing and is stamped `app`, so a website booking that loses the
/// header is counted as the app's in the salon's « Canaux ». Only the API is
/// faked here: `fetch` is the server.

const CONSUMER = 'myweli_web_at=access; myweli_web_rt=refresh';
const PRO = 'myweli_pro_at=access; myweli_pro_rt=refresh';
const SELECTION = {
  providerId: 'p1',
  serviceIds: ['s1'],
  appointmentDateTime: '2026-12-02T10:00:00Z',
};

function req(url: string, cookie: string, body: unknown, extra: Record<string, string> = {}) {
  return new NextRequest(`http://localhost${url}`, {
    method: 'POST',
    headers: { cookie, ...extra },
    body: JSON.stringify(body),
  });
}

type Sent = { url: string; channel: string | null };

/// The API: records each call's channel header. `expired` answers the first
/// call 401 so the BFF refreshes and asks again — the retry is a second
/// request, and it must say « web » too.
function api(mode: 'ok' | 'expired' = 'ok') {
  const sent: Sent[] = [];
  let first = true;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u.endsWith('/auth/refresh')) {
        return new Response(JSON.stringify({ accessToken: 'a2', refreshToken: 'r2' }), {
          status: 200,
        });
      }
      sent.push({ url: u, channel: new Headers(init?.headers).get('X-Myweli-Channel') });
      if (mode === 'expired' && first) {
        first = false;
        return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
      }
      return new Response(JSON.stringify({ id: 'appt1' }), { status: 201 });
    }),
  );
  return sent;
}

afterEach(() => vi.unstubAllGlobals());

describe('POST /api/bookings says the booking was made on the website', () => {
  it('sends X-Myweli-Channel: web to POST /appointments', async () => {
    const sent = api();
    expect((await book(req('/api/bookings', CONSUMER, SELECTION))).status).toBe(201);
    expect(sent).toHaveLength(1);
    expect(sent[0].url).toMatch(/\/appointments$/);
    expect(sent[0].channel).toBe('web');
  });

  it('says it again on the retry after a silent refresh', async () => {
    const sent = api('expired');
    expect((await book(req('/api/bookings', CONSUMER, SELECTION))).status).toBe(201);
    expect(sent).toHaveLength(2);
    expect(sent.map((s) => s.channel)).toEqual(['web', 'web']);
  });

  it('the browser cannot choose the channel', async () => {
    const sent = api();
    await book(req('/api/bookings', CONSUMER, SELECTION, { 'x-myweli-channel': 'app' }));
    expect(sent[0].channel).toBe('web');
  });
});

describe('and no other call says it', () => {
  it('a booking the salon enters (« Ajouter un rendez-vous ») does not', async () => {
    const sent = api();
    await bookForClient(req('/api/pro/appointments', PRO, SELECTION));
    expect(sent).toHaveLength(1);
    expect(sent[0].channel).toBeNull();
  });

  it('another consumer write (« Annuler ») does not', async () => {
    const sent = api();
    await cancelBooking(req('/api/appointments/a1/cancel', CONSUMER, {}), {
      params: { id: 'a1' },
    });
    expect(sent[0].channel).toBeNull();
  });
});
