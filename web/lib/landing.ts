import type { LocalityCity, LocalityTree } from './api/localities';
import { allAreas } from './api/localities';

/// SEO landing taxonomy — category side (multi-pays MP3,
/// docs/design/multi-pays-end-version.md §6). Categories are PRODUCT
/// taxonomy and stay code; geography comes from GET /localities and enters
/// every function as a parameter (pure + sync + testable). URLs are the
/// nested Planity tree: /coiffure → /coiffure/abidjan →
/// /coiffure/abidjan/cocody; legacy flat slugs (coiffure-cocody) 308 to it.
/// Supersedes docs/design/web-m4-landing.md's flat scheme.

export type Category = { slug: string; apiKey: string; label: string };

const categories: Category[] = [
  { slug: 'coiffure', apiKey: 'salon', label: 'Coiffure' },
  { slug: 'barbier', apiKey: 'barber', label: 'Barbier' },
  { slug: 'onglerie', apiKey: 'nail', label: 'Onglerie' },
  { slug: 'spa', apiKey: 'spa', label: 'Spa' },
  { slug: 'massage', apiKey: 'massage', label: 'Massage' },
];

/// The category vocabulary (read-only) — home tiles, /recherche chips,
/// search routing, the landing dispatcher.
export const categoryList: ReadonlyArray<Category> = categories;

export function categoryBySlug(slug: string): Category | null {
  return categories.find((c) => c.slug === slug) ?? null;
}

export function categorySlugForApiKey(apiKey: string): string | null {
  return categories.find((c) => c.apiKey === apiKey)?.slug ?? null;
}

/// The nested taxonomy path — shared by categories AND services (the URL
/// grammar is identical: /<root>/<city>/<area>).
export function buildTaxonomyPath(
  rootSlug: string,
  citySlug?: string,
  areaSlug?: string,
): string {
  if (!citySlug) return `/${rootSlug}`;
  if (!areaSlug) return `/${rootSlug}/${citySlug}`;
  return `/${rootSlug}/${citySlug}/${areaSlug}`;
}

export function buildLandingPath(
  categorySlug: string,
  citySlug?: string,
  areaSlug?: string,
): string {
  return buildTaxonomyPath(categorySlug, citySlug, areaSlug);
}

/// LEGACY flat slug (`coiffure-cocody`) → the nested path to permanently
/// redirect to, or null when it isn't a known category×area combo. Kept only
/// as a redirect recognizer — nothing builds flat slugs anymore.
export function parseFlatLanding(
  slug: string,
  tree: LocalityTree,
): string | null {
  const cat = categories.find((c) => slug.startsWith(`${c.slug}-`));
  if (!cat) return null;
  const areaSlug = slug.slice(cat.slug.length + 1);
  for (const { city, area } of allAreas(tree)) {
    if (area.slug === areaSlug) {
      return buildTaxonomyPath(cat.slug, city.slug, area.slug);
    }
  }
  return null;
}

/// Same root, the city's other areas (SEO internal links on the area level;
/// pass no `exceptAreaSlug` for the city page's area chips). Works for
/// categories and services alike — the root slug is opaque here.
export function siblingAreaLinks(
  rootSlug: string,
  city: LocalityCity,
  exceptAreaSlug?: string,
): { href: string; name: string }[] {
  return city.areas
    .filter((a) => a.slug !== exceptAreaSlug)
    .map((a) => ({
      href: buildTaxonomyPath(rootSlug, city.slug, a.slug),
      name: a.name,
    }));
}

/// The other categories at the same level (root, city or area page).
export function siblingCategoryLinks(
  exceptCategorySlug: string,
  citySlug?: string,
  areaSlug?: string,
): { href: string; label: string }[] {
  return categories
    .filter((c) => c.slug !== exceptCategorySlug)
    .map((c) => ({
      href: buildTaxonomyPath(c.slug, citySlug, areaSlug),
      label: c.label,
    }));
}
