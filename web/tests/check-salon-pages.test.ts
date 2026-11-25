// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
// @ts-expect-error — plain ESM with no declaration file; its runtime is what is tested.
import { check, verdict } from '../tool/check-salon-pages.mjs';

/// B18 — the daily production check (docs/design/web-salon-page-live-fallback.md
/// §8.3): every salon the API lists as public must be served by the BUILD. A
/// salon served live or answering 404 is checked once more after a wait (a
/// fresh validation is inside its build window); still not static, it fails.

describe('verdict', () => {
  it('only a 200 without the live header is static', () => {
    expect(verdict({ status: 200, live: false })).toBe('static');
    expect(verdict({ status: 200, live: true })).toBe('live');
    expect(verdict({ status: 404, live: false })).toBe('missing');
    expect(verdict({ status: 308, live: false })).toBe('error');
    expect(verdict({ status: 500, live: false })).toBe('error');
  });
});

/// A fake API + site: `pages` maps a slug to its answers, in order.
function world(slugs: string[], pages: Record<string, { status: number; live?: boolean }[]>) {
  const seen: Record<string, number> = {};
  return vi.fn(async (url: string, _init?: RequestInit) => {
    if (url.endsWith('/sitemap/providers')) {
      return new Response(JSON.stringify({ items: slugs.map((slug) => ({ slug })) }), { status: 200 });
    }
    const slug = url.split('/').pop() as string;
    const i = seen[slug] ?? 0;
    seen[slug] = i + 1;
    const a = pages[slug][Math.min(i, pages[slug].length - 1)];
    return new Response(null, {
      status: a.status,
      headers: a.live ? { 'x-myweli-salon-page': 'live' } : {},
    });
  });
}

const run = (fetchImpl: ReturnType<typeof world>, sleep = vi.fn(async () => {})) =>
  check({ api: 'https://api', site: 'https://site', fetchImpl, sleep, log: () => {} });

describe('check', () => {
  it('green when every public salon is static, with no wait', async () => {
    const sleep = vi.fn(async () => {});
    expect(await run(world(['a', 'b'], { a: [{ status: 200 }], b: [{ status: 200 }] }), sleep)).toEqual([]);
    expect(sleep).not.toHaveBeenCalled();
  });

  it('a salon inside its build window passes once its build lands', async () => {
    const sleep = vi.fn(async () => {});
    const fetchImpl = world(['a'], { a: [{ status: 200, live: true }, { status: 200 }] });
    expect(await run(fetchImpl, sleep)).toEqual([]);
    expect(sleep).toHaveBeenCalledWith(10 * 60 * 1000);
  });

  it('red for a salon still live, or still 404, after the wait', async () => {
    const fetchImpl = world(['a', 'b', 'c'], {
      a: [{ status: 200, live: true }],
      b: [{ status: 404 }],
      c: [{ status: 200 }],
    });
    expect(await run(fetchImpl)).toEqual([
      { slug: 'a', verdict: 'live' },
      { slug: 'b', verdict: 'missing' },
    ]);
  });

  it('never follows a redirect: a 307 to some 200 is not a page', async () => {
    const fetchImpl = world(['a'], { a: [{ status: 307 }] });
    expect(await run(fetchImpl)).toEqual([{ slug: 'a', verdict: 'error' }]);
    const pageCall = fetchImpl.mock.calls.find(([u]) => u === 'https://site/a');
    expect(pageCall?.[1]).toEqual({ redirect: 'manual' });
  });

  it('an unreadable API list is an error, not a green', async () => {
    const fetchImpl = vi.fn(async () => new Response('{}', { status: 503 }));
    await expect(run(fetchImpl as never)).rejects.toThrow(/503/);
  });
});
