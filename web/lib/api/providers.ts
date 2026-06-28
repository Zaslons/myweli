import { buildLandingSlug, categorySlugForApiKey } from '../landing';
import { api } from './client';
import type { components } from './schema';

export type Provider = components['schemas']['Provider'];
export type Service = components['schemas']['Service'];
export type Review = components['schemas']['Review'];
export type Artist = components['schemas']['Artist'];

/// Public provider read by slug (web M1 endpoint). Returns null on 404 / error
/// so pages can `notFound()` rather than crash an SSG/ISR render.
export async function getProviderBySlug(slug: string): Promise<Provider | null> {
  try {
    const { data, error } = await api.GET('/providers/by-slug/{slug}', {
      params: { path: { slug } },
    });
    if (error || !data) return null;
    return data;
  } catch {
    return null;
  }
}

/// All listable provider slugs (for generateStaticParams + the sitemap).
export async function getAllProviderSlugs(): Promise<string[]> {
  try {
    const { data } = await api.GET('/sitemap/providers', {});
    return (data?.items ?? [])
      .map((i) => i.slug)
      .filter((s): s is string => typeof s === 'string');
  } catch {
    return [];
  }
}

/// Providers in a category + commune, best-rated first (backs a landing page).
export async function listProviders(
  apiKey: string,
  commune: string,
): Promise<Provider[]> {
  try {
    const { data, error } = await api.GET('/providers', {
      params: { query: { category: apiKey, commune, sort: 'rating' } },
    });
    if (error || !data) return [];
    return data.items ?? [];
  } catch {
    return [];
  }
}

/// Landing slugs (category-commune) that actually have providers — for
/// generateStaticParams + the sitemap. Derived from the live catalogue.
export async function getLandingSlugs(): Promise<string[]> {
  try {
    const { data } = await api.GET('/providers', {
      params: { query: { pageSize: 50 } },
    });
    const seen = new Set<string>();
    for (const p of data?.items ?? []) {
      const catSlug = categorySlugForApiKey(p.category);
      if (!catSlug || !p.commune) continue;
      seen.add(buildLandingSlug(catSlug, p.commune));
    }
    return [...seen];
  } catch {
    return [];
  }
}
