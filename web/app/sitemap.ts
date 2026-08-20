import type { MetadataRoute } from 'next';
import { getLocalityTree } from '../lib/api/localities';
import {
  getAllProviderSlugs,
  getLandingParams,
  getServiceLandingParams,
} from '../lib/api/providers';
import { buildTaxonomyPath } from '../lib/landing';
import { LEGAL_ROUTES } from '../lib/legal';
import { siteUrl } from '../lib/seo/jsonld';
import { taxonomyRootSlugs } from '../lib/taxonomy';

export const revalidate = 3600;

/// Home + the nested landing tree (multi-pays MP3: roots → root×city →
/// root×city×area combos present in the catalogue) + provider pages.
/// Best-effort: everything falls back to empty if the API is unreachable, so
/// the build never fails. Legacy flat slugs are NOT listed — they 308.
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const tree = await getLocalityTree();
  const [providers, landings, serviceLandings] = await Promise.all([
    getAllProviderSlugs(),
    getLandingParams(tree),
    getServiceLandingParams(tree),
  ]);
  const entries: MetadataRoute.Sitemap = [
    { url: `${siteUrl}/`, changeFrequency: 'daily', priority: 1 },
    // L1 — the four legal documents. They join the HARD-CODED head because
    // everything below is API-derived and best-effort; a static route that is
    // not listed here is simply absent from the sitemap, silently.
    ...LEGAL_ROUTES.map((r) => ({
      url: `${siteUrl}${r.slug}`,
      changeFrequency: 'yearly' as const,
      priority: 0.3,
    })),
  ];
  // The three landing levels come from the LOCALITY TREE, not the catalogue.
  //
  // Until 2026-08-20 only the first two did: the third was taken from
  // `getLandingParams`/`getServiceLandingParams`, which list "combos present in
  // the catalogue". With production holding zero salons, that meant **187 live,
  // indexable, 200-answering pages were absent from the sitemap** —
  // `/coiffure/abidjan/cocody` and its siblings, each with its own title,
  // canonical and BreadcrumbList. The pages existed; nothing told a crawler.
  //
  // The tree knows every commune whether or not a salon has opened there, and a
  // landing page for an empty commune is exactly the page a crawler should find
  // first — it is how the first salon in that commune gets discovered.
  const cities = tree.countries.flatMap((c) => c.cities.map((x) => x.slug));
  const cityAreas = tree.countries.flatMap((c) =>
    c.cities.flatMap((city) =>
      (city.areas ?? []).map((area) => [city.slug, area.slug] as const),
    ),
  );
  for (const root of taxonomyRootSlugs()) {
    entries.push({
      url: `${siteUrl}${buildTaxonomyPath(root)}`,
      changeFrequency: 'weekly',
      priority: 0.5,
    });
    for (const city of cities) {
      entries.push({
        url: `${siteUrl}${buildTaxonomyPath(root, city)}`,
        changeFrequency: 'weekly',
        priority: 0.5,
      });
    }
    for (const [city, area] of cityAreas) {
      entries.push({
        url: `${siteUrl}${buildTaxonomyPath(root, city, area)}`,
        changeFrequency: 'weekly',
        priority: 0.4,
      });
    }
  }
  for (const p of [...landings, ...serviceLandings]) {
    entries.push({
      url: `${siteUrl}${buildTaxonomyPath(p.slug, p.city, p.area)}`,
      changeFrequency: 'weekly',
      priority: 0.6,
    });
  }
  for (const slug of providers) {
    entries.push({
      url: `${siteUrl}/${slug}`,
      changeFrequency: 'weekly',
      priority: 0.8,
    });
  }
  // The catalogue-derived levels above overlap the tree-derived ones by design —
  // both are correct, and a duplicated <loc> is a crawler-visible defect. First
  // entry wins, which keeps the higher priority the catalogue assigns.
  const seen = new Set<string>();
  return entries.filter((e) => !seen.has(e.url) && seen.add(e.url));
}
