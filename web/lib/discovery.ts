import { categoryList, communes } from './landing';
import { serviceSlugForQuery } from './service-landing';
import { normalize, slugify } from './slug';

/// Discovery search routing (pure, unit-tested): map the hero's two fields
/// (service + commune) to the best destination — an existing SEO landing when
/// both resolve, else the /recherche results page.

export function resolveCommune(text: string): string | null {
  const n = normalize(text);
  if (!n) return null;
  return communes.find((c) => normalize(c) === n) ?? null;
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
///  - category + commune → `/coiffure-cocody` (category landing)
///  - service  + commune → `/tresses-cocody` (service landing)
///  - otherwise          → `/recherche?q=&commune=`
export function resolveSearchHref(service: string, commune: string): string {
  const com = resolveCommune(commune);
  if (com) {
    const cat = resolveCategorySlug(service);
    if (cat) return `/${cat}-${slugify(com)}`;
    const svc = serviceSlugForQuery(service);
    if (svc) return `/${svc}-${slugify(com)}`;
  }
  const qs = new URLSearchParams();
  if (service.trim()) qs.set('q', service.trim());
  if (commune.trim()) qs.set('commune', commune.trim());
  const s = qs.toString();
  return s ? `/recherche?${s}` : '/recherche';
}
