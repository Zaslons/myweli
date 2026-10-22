import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/// docs/design/hygiene-batch9.md §2.10 (B9.11, decision Q6) — a public page
/// does not publish what it could not read.
///
/// `providers.ts` and `localities.ts` turned every failure — a 500, a dead
/// network, a 200 without its list — into an empty list (or, for one salon,
/// into « not found »). At ISR regeneration that REPLACED a good page with an
/// empty marketplace, or a live salon with a 404 for the whole window; at
/// build time it published a sitemap without its salons.
///
/// Where the build fails closed (production, local, CI — build-posture.ts),
/// such an answer now THROWS: Next keeps the last good page and tries again,
/// and a build fails while the previous deployment stays up. A Vercel
/// preview, whose staging API sleeps, keeps degrading. A real empty list, and
/// a real 404, are still that.

const GET = vi.fn();
vi.mock('../lib/api/client', () => ({ api: { GET } }));

const providers = await import('../lib/api/providers');
const localities = await import('../lib/api/localities');

const saved = process.env.VERCEL_ENV;
afterEach(() => {
  if (saved === undefined) delete process.env.VERCEL_ENV;
  else process.env.VERCEL_ENV = saved;
  GET.mockReset();
  localities.resetLocalityCache();
});

const ok = (data: unknown) => ({ data, response: new Response(null, { status: 200 }) });
const refused = (status: number) => ({
  error: { error: 'x' },
  response: new Response(null, { status }),
});
const tree = { countries: [{ code: 'CI', cities: [] }] };

/// Every list read, with the answer that is its list.
const LISTS: { name: string; call: () => Promise<unknown>; good: unknown }[] = [
  {
    name: 'getAllProviderSlugs',
    call: () => providers.getAllProviderSlugs(),
    good: { items: [{ slug: 'beaute-divine' }] },
  },
  {
    name: 'listProviders',
    call: () => providers.listProviders('hair', 'Cocody'),
    good: { items: [] },
  },
  {
    name: 'searchProviders',
    call: () => providers.searchProviders({ q: 'tresses' }),
    good: { items: [] },
  },
  {
    name: 'listProvidersByCommune',
    call: () => providers.listProvidersByCommune('Cocody'),
    good: { items: [] },
  },
  {
    name: 'getLandingParams',
    call: () => providers.getLandingParams(tree as never),
    good: { items: [] },
  },
  {
    name: 'getServiceLandingParams',
    call: () => providers.getServiceLandingParams(tree as never),
    good: { items: [] },
  },
];

describe('where the build fails closed (production, local, CI)', () => {
  beforeEach(() => {
    process.env.VERCEL_ENV = 'production';
  });

  for (const l of LISTS) {
    it(`${l.name}: a 500 throws`, async () => {
      GET.mockResolvedValue(refused(500));
      await expect(l.call()).rejects.toThrow();
    });

    it(`${l.name}: no answer throws`, async () => {
      GET.mockRejectedValue(new TypeError('fetch failed'));
      await expect(l.call()).rejects.toThrow();
    });

    it(`${l.name}: a 200 without its list throws`, async () => {
      GET.mockResolvedValue(ok({}));
      await expect(l.call()).rejects.toThrow();
    });

    it(`${l.name}: a real empty list is an empty list`, async () => {
      GET.mockResolvedValue(ok({ items: [] }));
      await expect(l.call()).resolves.toEqual([]);
    });
  }

  it('getAllProviderSlugs: the slugs', async () => {
    GET.mockResolvedValue(ok({ items: [{ slug: 'beaute-divine' }] }));
    expect(await providers.getAllProviderSlugs()).toEqual(['beaute-divine']);
  });

  it('getProviderBySlug: a real 404 is « no such salon »', async () => {
    GET.mockResolvedValue(refused(404));
    expect(await providers.getProviderBySlug('nope')).toBeNull();
  });

  it('getProviderBySlug: a 500 throws — not a 404 for a live salon', async () => {
    GET.mockResolvedValue(refused(500));
    await expect(providers.getProviderBySlug('beaute-divine')).rejects.toThrow();
  });

  it('getProviderBySlug: no answer throws', async () => {
    GET.mockRejectedValue(new TypeError('fetch failed'));
    await expect(providers.getProviderBySlug('beaute-divine')).rejects.toThrow();
  });

  it('getProviderBySlug: a 200 that is no salon throws', async () => {
    GET.mockResolvedValue(ok({}));
    await expect(providers.getProviderBySlug('beaute-divine')).rejects.toThrow();
  });

  it('getProviderBySlug: the salon', async () => {
    GET.mockResolvedValue(ok({ id: 'p1', slug: 'beaute-divine' }));
    expect(await providers.getProviderBySlug('beaute-divine')).toEqual({
      id: 'p1',
      slug: 'beaute-divine',
    });
  });

  it('getLocalityTree: a 500 throws, and the next call asks again', async () => {
    GET.mockResolvedValueOnce(refused(500)).mockResolvedValueOnce(ok(tree));
    await expect(localities.getLocalityTree()).rejects.toThrow();
    expect(await localities.getLocalityTree()).toEqual(tree);
    expect(GET).toHaveBeenCalledTimes(2);
  });

  it('getLocalityTree: a 200 without its countries throws', async () => {
    GET.mockResolvedValue(ok({}));
    await expect(localities.getLocalityTree()).rejects.toThrow();
  });
});

describe('on a Vercel preview (staging sleeps), the reads still degrade', () => {
  beforeEach(() => {
    process.env.VERCEL_ENV = 'preview';
  });

  for (const l of LISTS) {
    it(`${l.name}: a 500 is an empty list`, async () => {
      GET.mockResolvedValue(refused(500));
      await expect(l.call()).resolves.toEqual([]);
    });
  }

  it('getProviderBySlug: a 500 is null', async () => {
    GET.mockResolvedValue(refused(500));
    expect(await providers.getProviderBySlug('beaute-divine')).toBeNull();
  });

  it('getLocalityTree: a 500 is the empty tree', async () => {
    GET.mockResolvedValue(refused(500));
    expect(await localities.getLocalityTree()).toEqual({ countries: [] });
  });
});
