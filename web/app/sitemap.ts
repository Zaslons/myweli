import type { MetadataRoute } from 'next';
import {
  getAllProviderSlugs,
  getLandingSlugs,
  getServiceLandingSlugs,
} from '../lib/api/providers';
import { siteUrl } from '../lib/seo/jsonld';

export const revalidate = 3600;

/// Static pages + landing (category·commune + service·commune) pages + provider
/// pages. Best-effort: the helpers fall back to empty if the API is unreachable,
/// so the build never fails.
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const [providers, landings, serviceLandings] = await Promise.all([
    getAllProviderSlugs(),
    getLandingSlugs(),
    getServiceLandingSlugs(),
  ]);
  const entries: MetadataRoute.Sitemap = [
    { url: `${siteUrl}/`, changeFrequency: 'daily', priority: 1 },
  ];
  for (const slug of [...landings, ...serviceLandings]) {
    entries.push({
      url: `${siteUrl}/${slug}`,
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
