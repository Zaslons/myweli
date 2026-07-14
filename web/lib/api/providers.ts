import { categorySlugForApiKey } from '../landing';
import { serviceSlugsForName } from '../service-landing';
import { slugify } from '../slug';
import { api } from './client';
import { allAreas, type LocalityTree } from './localities';
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

/// Flexible discovery search/list (home featured + /recherche). Any of q /
/// category / commune; sorted by rating; bounded.
export async function searchProviders(opts: {
  q?: string;
  category?: string;
  commune?: string;
  pageSize?: number;
  /// FR-DISC-007 (parity 2.1/2.2): /recherche passes the user's choice;
  /// home/landing callers keep the default rating order.
  sort?: 'relevance' | 'rating' | 'price';
  availableToday?: boolean;
}): Promise<Provider[]> {
  try {
    const { data, error } = await api.GET('/providers', {
      params: {
        query: {
          ...(opts.q ? { q: opts.q } : {}),
          ...(opts.category ? { category: opts.category } : {}),
          ...(opts.commune ? { commune: opts.commune } : {}),
          ...(opts.availableToday ? { availableToday: true } : {}),
          sort: opts.sort ?? 'rating',
          pageSize: opts.pageSize ?? 12,
        },
      },
    });
    if (error || !data) return [];
    return data.items ?? [];
  } catch {
    return [];
  }
}

/// A landing route param triple ({slug}/{city}/{area}) — nested URLs
/// (multi-pays MP3).
export type LandingParams = { slug: string; city: string; area: string };

/// The salon's (city, area) slugs in the locality tree — from the MP1
/// `areaId` when present, else a slug match on the legacy commune name.
function areaParamsOf(
  p: Provider,
  tree: LocalityTree,
): { city: string; area: string } | null {
  const areaSlug = p.areaId ?? (p.commune ? slugify(p.commune) : null);
  if (!areaSlug) return null;
  for (const { city, area } of allAreas(tree)) {
    if (area.slug === areaSlug) return { city: city.slug, area: area.slug };
  }
  return null;
}

/// Category×area landing params that actually have providers — for
/// generateStaticParams + the sitemap. Derived from the live catalogue.
export async function getLandingParams(
  tree: LocalityTree,
): Promise<LandingParams[]> {
  try {
    const { data } = await api.GET('/providers', {
      params: { query: { pageSize: 50 } },
    });
    const seen = new Map<string, LandingParams>();
    for (const p of data?.items ?? []) {
      const catSlug = categorySlugForApiKey(p.category);
      const geo = areaParamsOf(p, tree);
      if (!catSlug || !geo) continue;
      const key = `${catSlug}/${geo.city}/${geo.area}`;
      seen.set(key, { slug: catSlug, ...geo });
    }
    return [...seen.values()];
  } catch {
    return [];
  }
}

/// Providers in a commune (all categories) — backs service landings, filtered
/// client-side by service name.
export async function listProvidersByCommune(
  commune: string,
): Promise<Provider[]> {
  try {
    const { data, error } = await api.GET('/providers', {
      params: { query: { commune, sort: 'rating' } },
    });
    if (error || !data) return [];
    return data.items ?? [];
  } catch {
    return [];
  }
}

/// Service×area landing params with ≥1 matching provider (catalogue-derived).
export async function getServiceLandingParams(
  tree: LocalityTree,
): Promise<LandingParams[]> {
  try {
    const { data } = await api.GET('/providers', {
      params: { query: { pageSize: 50 } },
    });
    const seen = new Map<string, LandingParams>();
    for (const p of data?.items ?? []) {
      const geo = areaParamsOf(p, tree);
      if (!geo) continue;
      for (const svc of p.services ?? []) {
        for (const slug of serviceSlugsForName(svc.name)) {
          seen.set(`${slug}/${geo.city}/${geo.area}`, { slug, ...geo });
        }
      }
    }
    return [...seen.values()];
  } catch {
    return [];
  }
}
