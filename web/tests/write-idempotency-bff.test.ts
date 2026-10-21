// @vitest-environment node
import { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { POST as cancelBooking } from '../app/api/appointments/[id]/cancel/route';
import { POST as book } from '../app/api/bookings/route';
import { POST as bookForClient } from '../app/api/pro/appointments/route';
import { POST as addNote } from '../app/api/pro/clients/[clientId]/notes/route';
import { POST as invite } from '../app/api/pro/members/route';
import { callApi } from '../lib/bff';
import { callApiPro } from '../lib/bff-pro';

/// docs/design/write-idempotency.md §4 — the BFF hands the browser's
/// `Idempotency-Key` to the API on the four creating POSTs, and on nothing
/// else. And an answer the API never gave back (the connection to it broke)
/// is a 502, the « lost answer » the browser asks again with the same key —
/// it used to escape the route as an unhandled throw. Only the API is faked
/// here: `fetch` is the server.

const KEY = 'web-key-00000001';
const CONSUMER = 'myweli_web_at=access; myweli_web_rt=refresh';
const PRO = 'myweli_pro_at=access; myweli_pro_rt=refresh';

function req(url: string, cookie: string, body: unknown, key?: string) {
  return new NextRequest(`http://localhost${url}`, {
    method: 'POST',
    headers: { cookie, ...(key ? { 'idempotency-key': key } : {}) },
    body: JSON.stringify(body),
  });
}

/// The API: records what it was sent; answers 201, or throws when told to.
function api(answer: 'ok' | 'throw' = 'ok') {
  const sent: { url: string; key: string | null }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      sent.push({
        url: String(url),
        key: new Headers(init?.headers).get('Idempotency-Key'),
      });
      if (answer === 'throw') throw new TypeError('fetch failed');
      return new Response(JSON.stringify({ id: 'x1' }), { status: 201 });
    }),
  );
  return sent;
}

afterEach(() => vi.unstubAllGlobals());

const FOUR: { name: string; run: (key?: string) => Promise<Response> }[] = [
  {
    name: 'POST /api/bookings',
    run: (key) =>
      book(
        req(
          '/api/bookings',
          CONSUMER,
          { providerId: 'p1', serviceIds: ['s1'], appointmentDateTime: '2026-10-22T10:00:00Z' },
          key,
        ),
      ),
  },
  {
    name: 'POST /api/pro/appointments',
    run: (key) =>
      bookForClient(
        req(
          '/api/pro/appointments',
          PRO,
          { providerId: 'p1', serviceIds: ['s1'], appointmentDateTime: '2026-10-22T10:00:00Z' },
          key,
        ),
      ),
  },
  {
    name: 'POST /api/pro/clients/{clientId}/notes',
    run: (key) =>
      addNote(req('/api/pro/clients/c1/notes', PRO, { providerId: 'p1', body: 'Allergie' }, key), {
        params: { clientId: 'c1' },
      }),
  },
  {
    name: 'POST /api/pro/members',
    run: (key) =>
      invite(req('/api/pro/members', PRO, { email: 'mgr@salon.ci', role: 'manager' }, key)),
  },
];

describe('the four creating POSTs', () => {
  for (const w of FOUR) {
    it(`${w.name}: the key reaches the API, as it came`, async () => {
      const sent = api();
      expect((await w.run(KEY)).status).toBe(201);
      expect(sent).toHaveLength(1);
      expect(sent[0].key).toBe(KEY);
    });

    it(`${w.name}: no key from the browser → none to the API`, async () => {
      const sent = api();
      await w.run();
      expect(sent[0].key).toBeNull();
    });

    it(`${w.name}: the API never answered → 502 bad_gateway, not a crash`, async () => {
      api('throw');
      const res = await w.run(KEY);
      expect(res.status).toBe(502);
      expect(await res.json()).toEqual({ error: 'bad_gateway' });
    });
  }
});

describe('and nothing else', () => {
  it('another write (« Annuler ») never forwards the key', async () => {
    const sent = api();
    await cancelBooking(req('/api/appointments/a1/cancel', CONSUMER, {}, KEY), {
      params: { id: 'a1' },
    });
    expect(sent[0].key).toBeNull();
  });

  it('the cores never forward it on their own', async () => {
    for (const [call, cookie] of [
      [callApi, CONSUMER],
      [callApiPro, PRO],
    ] as const) {
      const sent = api();
      await call(req('/api/x', cookie, {}, KEY), '/x', { method: 'POST', body: '{}' });
      expect(sent[0].key).toBeNull();
    }
  });

  it('both cores: an API that never answered is a 502 for any call', async () => {
    for (const [call, cookie] of [
      [callApi, CONSUMER],
      [callApiPro, PRO],
    ] as const) {
      api('throw');
      expect(await call(req('/api/x', cookie, {}), '/x', { method: 'POST', body: '{}' })).toEqual({
        status: 502,
        body: { error: 'bad_gateway' },
        tokens: undefined,
      });
    }
  });
});
