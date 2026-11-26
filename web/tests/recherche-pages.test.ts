import type { ReactElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/// docs/design/consumer-search.md §3.3 (A4w): `/recherche` reads pages 1 to N on the server —
/// N from `pages` in the address, 1 to 10 — so « Retour » from a salon and a reload show the
/// rows « Afficher plus » had shown. The rows are de-duplicated by id and the count is the
/// newest page's `total`; a page that cannot be read is a public read that cannot be read
/// (hygiene-batch9.md §2.10), never fewer salons and a wrong count.

const GET = vi.fn();
vi.mock('../lib/api/client', () => ({ api: { GET } }));
vi.mock('../lib/api/localities', () => ({ getLocalityTree: async () => ({ countries: [] }) }));

const { searchProviderPages } = await import('../lib/api/providers');
const { pagesFromParam, RECHERCHE_PAGE_SIZE, RECHERCHE_MAX_PAGES } = await import(
  '../lib/discovery/search-pages'
);
const RecherchePage = (await import('../app/recherche/page')).default;

const ok = (data: unknown) => ({ data, response: new Response(null, { status: 200 }) });
const ids = (from: number, to: number) =>
  Array.from({ length: to - from }, (_, i) => ({ id: `s${from + i}`, slug: `s${from + i}` }));

/// The server's pages of [total] salons, 24 each, for whatever page is asked.
function paged(total: number) {
  GET.mockImplementation(async (_path: string, init: { params: { query: Record<string, unknown> } }) => {
    const q = init.params.query;
    const p = Number(q.page);
    const size = Number(q.pageSize);
    return ok({ items: ids((p - 1) * size, Math.min(p * size, total)), page: p, pageSize: size, total });
  });
}

const saved = process.env.VERCEL_ENV;
beforeEach(() => {
  process.env.VERCEL_ENV = 'production';
});
afterEach(() => {
  if (saved === undefined) delete process.env.VERCEL_ENV;
  else process.env.VERCEL_ENV = saved;
  GET.mockReset();
});

describe('pagesFromParam: 1 to 10, anything else 1', () => {
  it('reads the pages', () => {
    expect(RECHERCHE_PAGE_SIZE).toBe(24);
    expect(RECHERCHE_MAX_PAGES).toBe(10);
    expect(pagesFromParam('1')).toBe(1);
    expect(pagesFromParam('3')).toBe(3);
    expect(pagesFromParam('10')).toBe(10);
  });

  it('outside 1–10, or not a whole number, is 1', () => {
    for (const raw of [undefined, '', '0', '-1', '11', '999', 'abc', '2.5', '1e1', ' 2']) {
      expect(pagesFromParam(raw), String(raw)).toBe(1);
    }
  });
});

describe('searchProviderPages', () => {
  it('reads pages 1 to N of 24, the same search each time', async () => {
    paged(63);
    const r = await searchProviderPages({ q: 'tresses', commune: 'Cocody', sort: 'rating' }, 3);
    expect(GET).toHaveBeenCalledTimes(3);
    const asked = GET.mock.calls.map((c) => c[1].params.query);
    expect(asked.map((q) => q.page).sort()).toEqual([1, 2, 3]);
    for (const q of asked) {
      expect(q).toMatchObject({ q: 'tresses', commune: 'Cocody', sort: 'rating', pageSize: 24 });
    }
    expect(r.items).toHaveLength(63);
    expect(r.items.map((p) => p.id).slice(0, 2)).toEqual(['s0', 's1']);
    expect(r.items.at(-1)!.id).toBe('s62');
    expect(r.total).toBe(63);
  });

  it('a salon on two pages is shown once', async () => {
    GET.mockImplementation(async (_p: string, init: { params: { query: { page: number } } }) =>
      init.params.query.page === 1
        ? ok({ items: ids(0, 24), page: 1, pageSize: 24, total: 47 })
        : ok({ items: ids(23, 47), page: 2, pageSize: 24, total: 47 }),
    );
    const r = await searchProviderPages({}, 2);
    expect(r.items).toHaveLength(47);
    expect(new Set(r.items.map((p) => p.id)).size).toBe(47);
  });

  it('a page whose answer has no total cannot be read — it throws where the build fails closed', async () => {
    GET.mockResolvedValue(ok({ items: ids(0, 24), page: 1, pageSize: 24 }));
    await expect(searchProviderPages({}, 1)).rejects.toThrow();
  });

  it('page 1 refused: it throws where the build fails closed', async () => {
    GET.mockResolvedValue({ error: { error: 'x' }, response: new Response(null, { status: 500 }) });
    await expect(searchProviderPages({}, 3)).rejects.toThrow();
  });

  it('a later page refused: the pages before it, and how many — the button offers the rest', async () => {
    paged(63);
    const good = GET.getMockImplementation()!;
    GET.mockImplementation(async (path: string, init: { params: { query: { page: number } } }) =>
      init.params.query.page === 2
        ? { error: { error: 'x' }, response: new Response(null, { status: 500 }) }
        : good(path, init),
    );
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const r = await searchProviderPages({ q: 'tresses' }, 3);
    expect(r.items).toHaveLength(24);
    expect(r.pages).toBe(1);
    expect(r.total).toBe(63);
    // Page 3 answered, but after a hole it is not shown.
    expect(r.items.some((p) => p.id === 's48')).toBe(false);
    expect(warn).toHaveBeenCalledOnce();
    expect(String(warn.mock.calls[0][0])).not.toContain('tresses');
    warn.mockRestore();
  });

  it('never past the last page page 1’s total says exists: pages=10 over 30 salons is 2 reads', async () => {
    paged(30);
    const r = await searchProviderPages({}, 10);
    expect(GET).toHaveBeenCalledTimes(2);
    expect(r).toMatchObject({ total: 30, pages: 2 });
    expect(r.items).toHaveLength(30);
    GET.mockClear();
    paged(0);
    expect(await searchProviderPages({}, 10)).toEqual({ items: [], total: 0, pages: 1 });
    expect(GET).toHaveBeenCalledTimes(1);
  });

  it('on a Vercel preview (staging sleeps) it degrades to nothing', async () => {
    process.env.VERCEL_ENV = 'preview';
    GET.mockResolvedValue({ error: { error: 'x' }, response: new Response(null, { status: 500 }) });
    expect(await searchProviderPages({}, 2)).toEqual({ items: [], total: 0, pages: 1 });
  });
});

describe('/recherche reads what the address asks', () => {
  type ClientProps = { results: { id: string }[]; total: number; pages: number };
  const clientProps = (el: ReactElement) =>
    (el.props as { children: ReactElement }).children.props as ClientProps;

  it('pages=2: two reads, 48 rows, the total, and pages 2 for the button', async () => {
    paged(63);
    const el = await RecherchePage({ searchParams: { q: 'tresses', pages: '2' } });
    expect(GET).toHaveBeenCalledTimes(2);
    const p = clientProps(el);
    expect(p.results).toHaveLength(48);
    expect(p.total).toBe(63);
    expect(p.pages).toBe(2);
  });

  it('no pages: one read of 24', async () => {
    paged(63);
    const p = clientProps(await RecherchePage({ searchParams: { q: 'tresses' } }));
    expect(GET).toHaveBeenCalledTimes(1);
    expect(p.results).toHaveLength(24);
    expect(p.pages).toBe(1);
  });

  it('a later page refused: pages 1 for the button, not the address’s 2', async () => {
    paged(63);
    const good = GET.getMockImplementation()!;
    GET.mockImplementation(async (path: string, init: { params: { query: { page: number } } }) =>
      init.params.query.page === 2
        ? { error: { error: 'x' }, response: new Response(null, { status: 500 }) }
        : good(path, init),
    );
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const p = clientProps(await RecherchePage({ searchParams: { pages: '2' } }));
    expect(p.results).toHaveLength(24);
    expect(p.pages).toBe(1);
    warn.mockRestore();
  });

  it('pages=99: read as 1, not 99 reads', async () => {
    paged(63);
    const p = clientProps(await RecherchePage({ searchParams: { pages: '99' } }));
    expect(GET).toHaveBeenCalledTimes(1);
    expect(p.pages).toBe(1);
  });

  it('the « Disponible aujourd’hui » and sort choices reach every page read', async () => {
    paged(63);
    await RecherchePage({ searchParams: { sort: 'price', dispo: '1', pages: '2' } });
    for (const c of GET.mock.calls) {
      expect(c[1].params.query).toMatchObject({ sort: 'price', availableToday: true, pageSize: 24 });
    }
  });
});
