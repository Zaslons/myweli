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

  // B0.19, decision 140 (docs/design/web-pro-account-deletion.md §6, §10 #16):
  // the Pro deletion page is indexed — the one /pro page a crawler is told
  // about — beside the legal documents, yearly, 0.3. It is not in LEGAL_ROUTES,
  // so it needs its own row; the e2e half fetches that row's <loc>.
  it('lists /pro/suppression-compte, as the legal documents are listed', async () => {
    const row = (await sitemap()).find((e) => e.url === `${siteUrl}/pro/suppression-compte`);
    expect(row, 'the Pro deletion page is not in the sitemap').toBeTruthy();
    expect(row!.changeFrequency).toBe('yearly');
    expect(row!.priority).toBe(0.3);
    // And it is the only /pro URL there: every other /pro page is noindex.
    const pro = (await sitemap()).map((e) => new URL(e.url).pathname).filter((p) => p === '/pro' || p.startsWith('/pro/'));
    expect(pro).toEqual(['/pro/suppression-compte']);
  });
});
