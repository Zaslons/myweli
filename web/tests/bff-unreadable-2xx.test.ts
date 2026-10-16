// @vitest-environment node
import type { NextRequest, NextResponse } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { GET as getAppointments } from '../app/api/appointments/route';
import { GET as getFavorites } from '../app/api/me/favorites/route';
import { type ApiResult, callApi, respond } from '../lib/bff';
import { callApiPro, respondPro } from '../lib/bff-pro';

/// docs/design/export-unreadable-200.md §2.1 / §4 — the BFFs no longer make a
/// 200 out of a lost body. `res.json().catch(() => ({}))` kept the server's
/// status, so a 2xx whose body was cut off on the way (or a proxy's HTML
/// page) reached the browser as a perfectly readable 200 `{}`, and #620's
/// guard in the browser (`readJson` → status 0) never fired. Then
/// `/api/me/favorites` turned `{}` into `{ favorites: [] }` and
/// `/api/appointments` into `items: []`: « Mes données » shipped empty
/// sections as complete. Only the API is faked here: `fetch` is the server.

function reqWith(cookies: Record<string, string>): NextRequest {
  return {
    cookies: {
      get: (k: string) => (cookies[k] ? { value: cookies[k] } : undefined),
    },
  } as unknown as NextRequest;
}

const consumer = reqWith({ myweli_web_at: 'access', myweli_web_rt: 'refresh' });
const pro = reqWith({ myweli_pro_at: 'access', myweli_pro_rt: 'refresh' });

/// The server's answers, one per request, in order.
function server(...answers: (() => Response)[]) {
  const urls: string[] = [];
  let i = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      urls.push(String(url));
      const answer = answers[Math.min(i, answers.length - 1)];
      i += 1;
      return answer();
    }),
  );
  return urls;
}

const json = (status: number, body: unknown) => () =>
  new Response(JSON.stringify(body), { status });
const htmlPage = () =>
  new Response('<html>Bad gateway</html>', {
    status: 200,
    headers: { 'content-type': 'text/html' },
  });
const cutOff = () => new Response('{"items":[{"id":"a1"', { status: 200 });
const expired = () => new Response(null, { status: 401 });
const rotated = json(200, { accessToken: 'na', refreshToken: 'nr' });

const BAD_GATEWAY = { error: 'bad_gateway' };

afterEach(() => vi.unstubAllGlobals());

const TWINS: {
  name: string;
  call: (path: string) => Promise<ApiResult>;
  respond: (r: ApiResult) => NextResponse;
  atCookie: string;
}[] = [
  {
    name: 'callApi (lib/bff.ts)',
    call: (path) => callApi(consumer, path),
    respond,
    atCookie: 'myweli_web_at',
  },
  {
    name: 'callApiPro (lib/bff-pro.ts)',
    call: (path) => callApiPro(pro, path),
    respond: respondPro,
    atCookie: 'myweli_pro_at',
  },
];

for (const twin of TWINS) {
  describe(`${twin.name} — a 2xx whose body cannot be read`, () => {
    it.each([
      ['an HTML page', htmlPage],
      ['a body cut off', cutOff],
    ])('a 200 holding %s → 502 bad_gateway, not a 200 `{}`', async (_label, answer) => {
      server(answer);

      const r = await twin.call('/me');

      expect(r).toEqual({ status: 502, body: BAD_GATEWAY });
      const res = twin.respond(r);
      expect(res.status).toBe(502);
      expect(await res.json()).toEqual(BAD_GATEWAY);
    });

    it('a 201 whose body is lost is a 502 too — not a 2xx the browser cannot use', async () => {
      server(() => new Response('', { status: 201 }));

      expect(await twin.call('/appointments')).toEqual({
        status: 502,
        body: BAD_GATEWAY,
      });
    });

    it('a 204 has no body and stays a 204', async () => {
      server(() => new Response(null, { status: 204 }));

      const r = await twin.call('/me');

      expect(r.status).toBe(204);
      const res = twin.respond(r);
      expect(res.status).toBe(204);
      expect(await res.text()).toBe('');
    });

    it('an error whose body cannot be read keeps its status, with `{}` as before', async () => {
      server(() => new Response('<html>Service unavailable</html>', { status: 503 }));

      expect(await twin.call('/me')).toEqual({ status: 503, body: {} });
    });

    it('a refresh, then a lost body: the 502 still re-cookies the rotated pair', async () => {
      // The server has spent the old refresh token: a 502 that dropped the
      // new pair would sign the user out on their next request.
      server(expired, rotated, htmlPage);

      const r = await twin.call('/me');

      expect(r).toEqual({
        status: 502,
        body: BAD_GATEWAY,
        tokens: { at: 'na', rt: 'nr' },
      });
      expect(twin.respond(r).headers.get('set-cookie')).toContain(
        `${twin.atCookie}=na`,
      );
    });

    it('CONTROL — a readable 200 is passed on as it came', async () => {
      server(json(200, { id: 'u1', name: 'Awa' }));

      expect(await twin.call('/me')).toEqual({
        status: 200,
        body: { id: 'u1', name: 'Awa' },
      });
    });
  });
}

describe('GET /api/me/favorites — a 200 without its list', () => {
  it.each([
    ['`{}`', {}],
    ['`providers: null`', { providerIds: ['p1'], providers: null }],
    ['`providers` a string', { providerIds: ['p1'], providers: 'x' }],
    ['`providers` an object', { providers: { p1: {} } }],
    ['a JSON `null`', null],
  ])('%s → 502, never `{ favorites: [] }`', async (_label, body) => {
    server(json(200, body));

    const res = await getFavorites(consumer);

    expect(res.status).toBe(502);
    expect(await res.json()).toEqual(BAD_GATEWAY);
  });

  it('the 502 keeps the refreshed session', async () => {
    server(expired, rotated, json(200, {}));

    const res = await getFavorites(consumer);

    expect(res.status).toBe(502);
    expect(res.headers.get('set-cookie')).toContain('myweli_web_at=na');
  });

  it('CONTROL — the list comes back as `favorites`, and an empty one is a real empty list', async () => {
    const salon = { id: 'p1', name: 'Beauté Divine', status: 'active' };
    server(json(200, { providerIds: ['p1'], providers: [salon] }));
    let res = await getFavorites(consumer);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ favorites: [salon] });

    server(json(200, { providerIds: [], providers: [] }));
    res = await getFavorites(consumer);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ favorites: [] });
  });

  it('CONTROL — a refusal passes as it came', async () => {
    server(json(403, { error: 'forbidden' }));

    const res = await getFavorites(consumer);

    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'forbidden' });
  });
});

describe('GET /api/appointments — a 200 without its list', () => {
  it.each([
    ['`{}`', {}],
    ['`items: null`', { items: null, page: 1, pageSize: 0, total: 0 }],
    // Was a TypeError in the route — a Next 500 — rather than a 502.
    ['`items` a string', { items: 'x' }],
    ['a JSON `null`', null],
  ])('%s → 502, never `items: []`', async (_label, body) => {
    server(json(200, body));

    const res = await getAppointments(consumer);

    expect(res.status).toBe(502);
    expect(await res.json()).toEqual(BAD_GATEWAY);
  });

  it('the 502 keeps the refreshed session', async () => {
    server(expired, rotated, json(200, {}));

    const res = await getAppointments(consumer);

    expect(res.status).toBe(502);
    expect(res.headers.get('set-cookie')).toContain('myweli_web_at=na');
  });

  it('CONTROL — each booking is marked `salonEntered`, the envelope kept; an empty list stays a 200', async () => {
    server(
      json(200, {
        items: [
          { id: 'a1', userId: 'u1' },
          { id: 'a2', userId: 'manual' },
        ],
        page: 1,
        pageSize: 2,
        total: 2,
      }),
    );
    let res = await getAppointments(consumer);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      items: [
        { id: 'a1', userId: 'u1', salonEntered: false },
        { id: 'a2', userId: 'manual', salonEntered: true },
      ],
      page: 1,
      pageSize: 2,
      total: 2,
    });

    server(json(200, { items: [], page: 1, pageSize: 0, total: 0 }));
    res = await getAppointments(consumer);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ items: [], page: 1, pageSize: 0, total: 0 });
  });

  it('CONTROL — a refusal passes as it came', async () => {
    server(json(403, { error: 'forbidden' }));

    const res = await getAppointments(consumer);

    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'forbidden' });
  });
});
