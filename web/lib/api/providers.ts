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
