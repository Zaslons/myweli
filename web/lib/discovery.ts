import type { LocalityTree } from './api/localities';
import { allAreas } from './api/localities';
import { buildTaxonomyPath, categoryList } from './landing';
import { serviceSlugForQuery } from './service-landing';
import { normalize, slugify } from './slug';

/// Discovery search routing (pure, unit-tested): map the hero's two fields
/// (service + commune/quartier) to the best destination — a nested SEO
/// landing when both resolve, else the /recherche results page. Geography
/// comes from the locality tree (multi-pays MP3).

export type ResolvedArea = { citySlug: string; areaSlug: string; name: string };

/// Accent/case-insensitive area-name match against the tree.
export function resolveArea(
  text: string,
  tree: LocalityTree,
): ResolvedArea | null {
  const n = normalize(text).trim();
  if (!n) return null;
  for (const { city, area } of allAreas(tree)) {
    if (normalize(area.name) === n || area.slug === slugify(text)) {
      return { citySlug: city.slug, areaSlug: area.slug, name: area.name };
    }
  }
  return null;
}

export function resolveCategorySlug(text: string): string | null {
  const n = normalize(text);
  if (!n) return null;
  const c = categoryList.find(
    (x) => x.slug === slugify(text) || normalize(x.label) === n,
  );
  return c?.slug ?? null;
}

/// service+commune → href:
///  - category + area → `/coiffure/abidjan/cocody` (category landing)
///  - service  + area → `/tresses/abidjan/cocody` (service landing)
///  - otherwise       → `/recherche?q=&commune=`
export function resolveSearchHref(
  service: string,
  commune: string,
  tree: LocalityTree,
): string {
  const area = resolveArea(commune, tree);
  if (area) {
    const cat = resolveCategorySlug(service);
    if (cat) return buildTaxonomyPath(cat, area.citySlug, area.areaSlug);
    const svc = serviceSlugForQuery(service);
    if (svc) return buildTaxonomyPath(svc, area.citySlug, area.areaSlug);
  }
  const qs = new URLSearchParams();
  if (service.trim()) qs.set('q', service.trim());
  if (commune.trim()) qs.set('commune', commune.trim());
  const s = qs.toString();
  return s ? `/recherche?${s}` : '/recherche';
}
