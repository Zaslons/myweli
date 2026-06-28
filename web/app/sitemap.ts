import type { MetadataRoute } from 'next';
import { siteUrl } from '../lib/seo/jsonld';

const apiBase =
  process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8080';

export const revalidate = 3600;

/// Static pages + every listable provider slug (from `GET /sitemap/providers`).
/// Best-effort: if the API is unreachable at build time, fall back to static
/// pages so the build never fails.
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const staticEntries: MetadataRoute.Sitemap = [
    { url: `${siteUrl}/`, changeFrequency: 'daily', priority: 1 },
  ];
  try {
    const res = await fetch(`${apiBase}/sitemap/providers`, {
      next: { revalidate: 3600 },
    });
    if (!res.ok) return staticEntries;
    const body = (await res.json()) as { items?: { slug?: string }[] };
    const providers: MetadataRoute.Sitemap = (body.items ?? [])
      .filter((p): p is { slug: string } => typeof p.slug === 'string')
      .map((p) => ({
        url: `${siteUrl}/${p.slug}`,
        changeFrequency: 'weekly',
        priority: 0.8,
      }));
    return [...staticEntries, ...providers];
  } catch {
    return staticEntries;
  }
}
