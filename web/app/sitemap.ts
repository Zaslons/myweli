import type { MetadataRoute } from 'next';
import { getLocalityTree } from '../lib/api/localities';
import {
  getAllProviderSlugs,
  getLandingParams,
  getServiceLandingParams,
} from '../lib/api/providers';
import { buildTaxonomyPath } from '../lib/landing';
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
  ];
  const cities = tree.countries.flatMap((c) => c.cities.map((x) => x.slug));
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
  return entries;
}
