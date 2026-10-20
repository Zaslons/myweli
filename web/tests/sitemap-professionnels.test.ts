import { afterAll, describe, expect, it, vi } from 'vitest';

// A preview degrades an empty locality tree to zero landing pages instead of
// refusing to build (legacy-redirects.test.ts) — this file needs no city.
const savedEnv = process.env.VERCEL_ENV;
process.env.VERCEL_ENV = 'preview';
afterAll(() => {
  if (savedEnv === undefined) delete process.env.VERCEL_ENV;
  else process.env.VERCEL_ENV = savedEnv;
});

// The sitemap's data reads: empty answers — this file is about one static row.
vi.mock('../lib/api/localities', () => ({ getLocalityTree: async () => ({ countries: [] }) }));
vi.mock('../lib/api/providers', () => ({
  getAllProviderSlugs: async () => [],
  getLandingParams: async () => [],
  getServiceLandingParams: async () => [],
}));

const { default: sitemap } = await import('../app/sitemap');
const { siteUrl } = await import('../lib/seo/jsonld');

/// « MyWeli Pro pour les salons » is a page to be FOUND
/// (docs/design/web-pro-access.md §4): it ships in the sitemap, beside the
/// support page and the legal documents.
describe('sitemap', () => {
  it('lists /professionnels', async () => {
    const urls = (await sitemap()).map((e) => e.url);
    expect(urls).toContain(`${siteUrl}/professionnels`);
  });
});
