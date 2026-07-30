import { categoryList, type Category } from './landing';
import { serviceList, type ServiceDef } from './service-landing';

/// The SEO taxonomy roots (multi-pays MP3): 5 categories + 13 curated
/// services share ONE nested URL grammar (/<root>/<city>/<area>). The
/// backend reserves exactly these slugs for provider slugs
/// (backend/lib/src/slug.dart), so a root can never be shadowed by a salon.

export type TaxonomyRoot =
  | { kind: 'category'; slug: string; label: string; category: Category }
  | { kind: 'service'; slug: string; label: string; service: ServiceDef };

/// Resolve a first-segment slug to a taxonomy root. Categories win the one
/// overlap (`massage` is both) — same precedence the flat scheme had.
export function resolveTaxonomyRoot(slug: string): TaxonomyRoot | null {
  const category = categoryList.find((c) => c.slug === slug);
  if (category) {
    return { kind: 'category', slug, label: category.label, category };
  }
  const service = serviceList.find((s) => s.slug === slug);
  if (service) return { kind: 'service', slug, label: service.label, service };
  return null;
}

/// Every root slug, deduplicated (generateStaticParams + the sitemap).
export function taxonomyRootSlugs(): string[] {
  return [
    ...new Set([
      ...categoryList.map((c) => c.slug),
      ...serviceList.map((s) => s.slug),
    ]),
  ];
}
