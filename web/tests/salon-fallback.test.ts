// @vitest-environment node
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { getMiddlewareMatchers } from 'next/dist/build/analysis/get-page-static-info';
import { NextRequest } from 'next/server';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildFailsClosed } from '../lib/build-posture';
import {
  NOWHERE,
  decide,
  route,
  staticSalonSlugs,
  type SalonLists,
} from '../lib/salon-fallback';
import { taxonomyRootSlugs } from '../lib/taxonomy';
// @ts-expect-error — plain ESM with no declaration file; its runtime is what is tested.
import * as buildList from '../tool/salon-build-list.mjs';

/// B18 — the « live fallback » (docs/design/web-salon-page-live-fallback.md §8.2).
/// A salon that is public but not yet in the build is served live at its own
/// address; everything else is routed as before, and only an unknown
/// salon-shaped slug ever costs an API read.

const ROUTES: string[] = buildList.topLevelRoutes(resolve(__dirname, '../app'));

const GET = vi.fn();
vi.mock('../lib/api/client', () => ({ api: { GET } }));
// The page module pulls in the whole salon view; its rendering is not what is
// tested here, its params are.
vi.mock('../components/provider/ProviderView', () => ({
  ProviderView: () => null,
  providerMetadata: () => ({}),
}));
vi.mock('../components/landing/TaxonomyLandingView', () => ({
  TaxonomyLandingView: () => null,
  taxonomyMetadata: () => ({}),
}));

const saved = { ...process.env };
afterEach(() => {
  process.env = { ...saved };
  GET.mockReset();
  vi.useRealTimers();
});

const lists: SalonLists = {
  built: new Set(['beaute-divine']),
  routes: new Set(ROUTES),
  roots: new Set(taxonomyRootSlugs()),
};

describe('decide — what costs an API read', () => {
  it('a built salon, a route of the site and a taxonomy root never do', () => {
    expect(decide('/beaute-divine', lists)).toEqual({ kind: 'pass' });
    for (const r of ROUTES) expect(decide(`/${r}`, lists), r).toEqual({ kind: 'pass' });
    for (const r of taxonomyRootSlugs()) expect(decide(`/${r}`, lists), r).toEqual({ kind: 'pass' });
  });

  it('the route list holds the routes a salon must never shadow', () => {
    expect(ROUTES).toEqual(
      expect.arrayContaining(['api', 'cgu', 'connexion', 'mon-compte', 'pro', 'recherche', 'support']),
    );
    expect(ROUTES.some((r) => r.startsWith('[') || r.startsWith('_'))).toBe(false);
  });

  it('nothing that is not salon-shaped does', () => {
    for (const p of ['/', '/a--b', '/-a', '/a-', '/Test-3', '/a.b', '/favicon.ico', '/x/y', '/test-3/reserver']) {
      expect(decide(p, lists), p).toEqual({ kind: 'pass' });
    }
  });

  it('an unknown salon-shaped slug does', () => {
    expect(decide('/test-3', lists)).toEqual({ kind: 'ask', slug: 'test-3' });
  });

  it('the live route, named directly, is hidden', () => {
    for (const p of ['/recherche/salon', '/recherche/salon/x', '/recherche/salon/x/y']) {
      expect(decide(p, lists), p).toEqual({ kind: 'hide' });
    }
    expect(decide('/recherche', lists)).toEqual({ kind: 'pass' });
  });
});

describe('route — the whole fallback, with the read injected', () => {
  it('rewrites a public salon to the live route, marked live', async () => {
    const ask = vi.fn(async () => true);
    expect(await route('/test-3', lists, ask)).toEqual({
      kind: 'rewrite',
      pathname: '/recherche/salon/test-3',
      live: true,
    });
    expect(ask).toHaveBeenCalledWith('test-3');
  });

  it('passes on « not public », and on a read that throws', async () => {
    expect(await route('/test-3', lists, async () => false)).toEqual({ kind: 'pass' });
    expect(
      await route('/test-3', lists, async () => {
        throw new Error('down');
      }),
    ).toEqual({ kind: 'pass' });
  });

  it('never asks about a built salon or the live route itself', async () => {
    const ask = vi.fn(async () => true);
    expect(await route('/beaute-divine', lists, ask)).toEqual({ kind: 'pass' });
    expect(await route('/recherche/salon/test-3', lists, ask)).toEqual({
      kind: 'rewrite',
      pathname: NOWHERE,
      live: false,
    });
    expect(ask).not.toHaveBeenCalled();
    expect(NOWHERE.split('/').filter(Boolean).length, 'four segments match no route').toBe(4);
  });
});

describe('middleware.ts — the real wiring, the API mocked', () => {
  beforeEach(() => {
    process.env.MYWELI_BUILT_SALON_SLUGS = JSON.stringify(['beaute-divine']);
    process.env.MYWELI_TOP_LEVEL_ROUTES = JSON.stringify(ROUTES);
    vi.resetModules();
  });
  const load = async () => (await import('../middleware')).middleware;
  const req = (path: string) => new NextRequest(`https://myweli.com${path}`);
  const rewriteOf = (res: Response) => res.headers.get('x-middleware-rewrite');
  const passed = (res: Response) =>
    res.headers.get('x-middleware-next') === '1' && rewriteOf(res) === null;

  it('a public salon not in the build: rewritten live, query kept, header set', async () => {
    GET.mockResolvedValue({ data: { id: 'p9' }, response: new Response(null, { status: 200 }) });
    const res = await (await load())(req('/test-3?_rsc=abc'));
    expect(rewriteOf(res)).toBe('https://myweli.com/recherche/salon/test-3?_rsc=abc');
    expect(res.headers.get('x-myweli-salon-page')).toBe('live');
    expect(GET).toHaveBeenCalledTimes(1);
    expect(GET.mock.calls[0][0]).toBe('/providers/by-slug/{slug}');
    expect(GET.mock.calls[0][1].params).toEqual({ path: { slug: 'test-3' } });
  });

  it('404, 500, a 200 without a salon and a network error all pass, never throw', async () => {
    const answers = [
      { error: { error: 'not_found' }, response: new Response(null, { status: 404 }) },
      { error: { error: 'x' }, response: new Response(null, { status: 500 }) },
      { data: {}, response: new Response(null, { status: 200 }) },
    ];
    const middleware = await load();
    for (const a of answers) {
      GET.mockResolvedValueOnce(a);
      const res = await middleware(req('/test-3'));
      expect(passed(res), `status ${a.response.status}`).toBe(true);
      expect(res.headers.get('x-myweli-salon-page')).toBeNull();
    }
    GET.mockRejectedValueOnce(new TypeError('fetch failed'));
    expect(passed(await middleware(req('/test-3')))).toBe(true);
  });

  it('gives up after two seconds and passes', async () => {
    vi.useFakeTimers();
    GET.mockImplementation(
      (_path: string, init: { signal: AbortSignal }) =>
        new Promise((_, reject) =>
          init.signal.addEventListener('abort', () => reject(new Error('aborted'))),
        ),
    );
    const pending = (await load())(req('/test-3'));
    await vi.advanceTimersByTimeAsync(2000);
    expect(passed(await pending)).toBe(true);
  });

  it('a built salon and a route of the site cost no read', async () => {
    const middleware = await load();
    for (const p of ['/beaute-divine', '/cgu', '/recherche', '/coiffure']) {
      expect(passed(await middleware(req(p))), p).toBe(true);
    }
    expect(GET).not.toHaveBeenCalled();
  });

  it('the live route named directly goes nowhere, with no read', async () => {
    const res = await (await load())(req('/recherche/salon/beaute-divine'));
    expect(rewriteOf(res)).toBe(`https://myweli.com${NOWHERE}`);
    expect(GET).not.toHaveBeenCalled();
  });
});

describe('the matcher, compiled by Next itself', () => {
  const runs = (matchers: { regexp: string }[], path: string) =>
    matchers.some((m) => new RegExp(m.regexp).test(path));

  it('takes a salon path and the live route, and nothing else', async () => {
    process.env.MYWELI_TOP_LEVEL_ROUTES = '[]';
    const { config } = await import('../middleware');
    const matchers = getMiddlewareMatchers(config.matcher, {} as never);
    expect(runs(matchers, '/test-3')).toBe(true);
    expect(runs(matchers, '/recherche/salon/x')).toBe(true);
    expect(runs(matchers, '/recherche/salon')).toBe(true);
    expect(runs(matchers, '/test-3/reserver')).toBe(false);
    expect(runs(matchers, '/favicon.ico')).toBe(false);
    expect(runs(matchers, '/coiffure/abidjan/cocody')).toBe(false);
  });

  it('the control: a bare « /:slug » would take no salon path at all', () => {
    // Next 14.2 appends `(.json)?`, which path-to-regexp reads as the
    // parameter's own pattern. This is why the matcher spells its pattern out.
    expect(runs(getMiddlewareMatchers(['/:slug'], {} as never), '/test-3')).toBe(false);
  });
});

describe('one list per build', () => {
  it('generateStaticParams builds the inlined list and the roots, and reads no API', async () => {
    process.env.MYWELI_BUILT_SALON_SLUGS = JSON.stringify(['salon-a', 'salon-b']);
    vi.resetModules();
    const { generateStaticParams } = await import('../app/[slug]/page');
    const slugs = (await generateStaticParams()).map((p) => p.slug);
    expect(slugs).toEqual(expect.arrayContaining(['salon-a', 'salon-b', ...taxonomyRootSlugs()]));
    expect(slugs).toHaveLength(2 + taxonomyRootSlugs().length);
    expect(GET).not.toHaveBeenCalled();
  });

  it('no inlined list: refused in a production build that fails closed, empty elsewhere', () => {
    delete process.env.MYWELI_BUILT_SALON_SLUGS;
    expect(() => staticSalonSlugs({ NODE_ENV: 'production' })).toThrow(/prebuild/);
    expect(() =>
      staticSalonSlugs({ NODE_ENV: 'production', VERCEL_ENV: 'production' }),
    ).toThrow(/prebuild/);
    expect(staticSalonSlugs({ NODE_ENV: 'production', VERCEL_ENV: 'preview' })).toEqual([]);
    expect(staticSalonSlugs({ NODE_ENV: 'development' })).toEqual([]);
  });
});

describe('tool/salon-build-list.mjs — the prebuild', () => {
  const answer = (status: number, body: unknown) => async (_url?: string, _init?: RequestInit) =>
    new Response(JSON.stringify(body), { status });

  it('one read: the string slugs, sorted and deduplicated', async () => {
    const fetchImpl = vi.fn(answer(200, { items: [{ slug: 'b' }, { slug: 'a' }, { slug: 'b' }, {}] }));
    expect(await buildList.fetchSalonSlugs({ base: 'http://api/', fetchImpl, env: {} })).toEqual([
      'a',
      'b',
    ]);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(fetchImpl.mock.calls[0][0]).toBe('http://api/sitemap/providers');
  });

  it('an unreadable list fails the build where it fails closed, and is empty on a preview', async () => {
    const failures = [
      answer(500, {}),
      answer(200, { nope: [] }),
      async () => {
        throw new TypeError('fetch failed');
      },
    ];
    for (const fetchImpl of failures) {
      for (const env of [{}, { VERCEL_ENV: 'production' }]) {
        await expect(buildList.fetchSalonSlugs({ base: 'http://api', fetchImpl, env })).rejects.toThrow(
          /could not be read/,
        );
      }
      expect(
        await buildList.fetchSalonSlugs({ base: 'http://api', fetchImpl, env: { VERCEL_ENV: 'preview' } }),
      ).toEqual([]);
    }
  });

  it('its posture is the build posture', () => {
    for (const env of [{}, { VERCEL_ENV: 'production' }, { VERCEL_ENV: 'preview' }, { VERCEL_ENV: 'development' }]) {
      expect(buildList.failsClosed(env), JSON.stringify(env)).toBe(buildFailsClosed(env));
    }
  });

  it('the file: absent is null, well-formed is its slugs, anything else is an error', () => {
    const dir = mkdtempSync(join(tmpdir(), 'salon-list-'));
    expect(buildList.readSalonListFile(join(dir, 'missing.json'))).toBeNull();
    writeFileSync(join(dir, 'ok.json'), JSON.stringify({ slugs: ['a'], readAt: 'x' }));
    expect(buildList.readSalonListFile(join(dir, 'ok.json'))).toEqual(['a']);
    writeFileSync(join(dir, 'bad.json'), JSON.stringify({ items: [] }));
    expect(() => buildList.readSalonListFile(join(dir, 'bad.json'))).toThrow(/slugs/);
    writeFileSync(join(dir, 'broken.json'), '{');
    expect(() => buildList.readSalonListFile(join(dir, 'broken.json'))).toThrow();
  });

  it('the routes: groups are read through; dynamic, private and slot folders are not routes', () => {
    const app = mkdtempSync(join(tmpdir(), 'app-'));
    for (const d of ['cgu', '[slug]', '_private', '@modal', '(marketing)/offres', '(marketing)/[x]']) {
      mkdirSync(join(app, d), { recursive: true });
    }
    writeFileSync(join(app, 'page.tsx'), '');
    expect(buildList.topLevelRoutes(app)).toEqual(['cgu', 'offres']);
  });
});
