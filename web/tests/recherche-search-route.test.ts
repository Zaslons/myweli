// @vitest-environment node
import type { NextRequest } from 'next/server';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/// docs/design/consumer-search.md §3.3 (A4w): `GET /api/recherche`, the same-origin
/// route « Afficher plus » reads (the browser never calls the API host, lib/api/client.ts).
/// It forwards the search's own fields and nothing else, fixes the page size at 24 itself,
/// and a lost body is « we could not ask », never a page of nothing.

const GET_ROUTE = (await import('../app/api/recherche/route')).GET;

function req(query: string): NextRequest {
  const url = new URL(`https://myweli.com/api/recherche?${query}`);
  return { nextUrl: url } as unknown as NextRequest;
}

let asked: string[];
let inits: (RequestInit | undefined)[];
function server(answer: () => Response) {
  asked = [];
  inits = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      asked.push(String(url));
      inits.push(init);
      return answer();
    }),
  );
}
const page = { items: [{ id: 's24' }], page: 2, pageSize: 24, total: 63 };

beforeEach(() => server(() => new Response(JSON.stringify(page), { status: 200 })));
afterEach(() => vi.unstubAllGlobals());

const forwarded = () => {
  expect(asked).toHaveLength(1);
  const u = new URL(asked[0]);
  expect(u.pathname.endsWith('/providers')).toBe(true);
  return Object.fromEntries(u.searchParams);
};

describe('GET /api/recherche', () => {
  it('forwards the search’s fields and the page; the page size is the route’s, 24', async () => {
    const res = await GET_ROUTE(
      req('q=tresses&commune=Cocody&category=salon&sort=rating&availableToday=true&page=3'),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual(page);
    expect(forwarded()).toEqual({
      q: 'tresses',
      commune: 'Cocody',
      category: 'salon',
      sort: 'rating',
      availableToday: 'true',
      page: '3',
      pageSize: '24',
    });
  });

  it('asks the API afresh each time: Next 14 would otherwise cache the read', async () => {
    await GET_ROUTE(req('q=tresses&page=2'));
    expect(inits[0]?.cache).toBe('no-store');
  });

  it('drops what is not the search’s, and a page size the caller sent', async () => {
    await GET_ROUTE(req('q=tresses&pageSize=50&ownerId=u1&status=draft&page=2'));
    expect(forwarded()).toEqual({ q: 'tresses', page: '2', pageSize: '24' });
  });

  it('a page that is not a whole number from 1 is page 1', async () => {
    for (const p of ['0', '-2', 'abc', '2.5', '']) {
      server(() => new Response(JSON.stringify(page), { status: 200 }));
      await GET_ROUTE(req(`q=tresses&page=${p}`));
      expect(forwarded().page, `page=${p}`).toBe('1');
    }
  });

  it('an empty field is not sent', async () => {
    await GET_ROUTE(req('q=&commune=&page=2'));
    expect(forwarded()).toEqual({ page: '2', pageSize: '24' });
  });

  it('the server’s refusal keeps its status and its body', async () => {
    server(() => new Response(JSON.stringify({ error: 'invalid_query' }), { status: 400 }));
    const res = await GET_ROUTE(req('q=%01&page=2'));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: 'invalid_query' });
  });

  it('a 200 whose body is lost is 502, never a page of nothing', async () => {
    server(() => new Response('{"items":[{"id":"s2', { status: 200 }));
    const res = await GET_ROUTE(req('q=tresses&page=2'));
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: 'bad_gateway' });
  });
});
