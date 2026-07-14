import type { LocalityTree } from './api/localities';
import { allAreas } from './api/localities';
import { buildTaxonomyPath } from './landing';
import { normalize, slugify } from './slug';

/// SEO landing taxonomy — service side (multi-pays MP3). The 13 curated
/// services (PRD Appendix A) stay code; providers are matched client-side by
/// service name (the API has no service filter). Geography enters as a
/// parameter; URLs are the nested tree (/tresses/abidjan/cocody) with flat
/// slugs (tresses-cocody) as 308 redirect recognizers only. Supersedes
/// docs/design/web-m4-1-service-landing.md's flat scheme.

export type ServiceDef = { slug: string; label: string; keywords: string[] };

const services: ServiceDef[] = [
  { slug: 'tresses', label: 'Tresses & nattes', keywords: ['tresse', 'natte', 'vanille', 'box', 'braid'] },
  { slug: 'tissage', label: 'Tissage', keywords: ['tissage', 'weave'] },
  { slug: 'defrisage', label: 'Défrisage', keywords: ['defrisage', 'lissage'] },
  { slug: 'coupe-homme', label: 'Coupe homme & dégradé', keywords: ['degrade', 'fade', 'coupe homme'] },
  { slug: 'barbe', label: 'Taille de barbe', keywords: ['barbe', 'rasage'] },
  { slug: 'coupe-femme', label: 'Coupe femme', keywords: ['coupe femme', 'brushing'] },
  { slug: 'locks', label: 'Locks', keywords: ['locks', 'dread'] },
  { slug: 'coloration', label: 'Coloration', keywords: ['coloration', 'couleur'] },
  { slug: 'manucure', label: 'Manucure', keywords: ['manucure'] },
  { slug: 'pedicure', label: 'Pédicure', keywords: ['pedicure'] },
  { slug: 'ongles', label: "Pose d'ongles", keywords: ['ongle', 'gel', 'capsule', 'vernis', 'nail'] },
  { slug: 'massage', label: 'Massage', keywords: ['massage'] },
  { slug: 'soin-visage', label: 'Soin du visage', keywords: ['soin du visage', 'soin visage', 'gommage', 'facial'] },
];

const bySlug = new Map(services.map((s) => [s.slug, s]));

/// The service vocabulary (read-only) — root dispatch + sibling links.
export const serviceList: ReadonlyArray<ServiceDef> = services;

export function serviceBySlug(slug: string): ServiceDef | null {
  return bySlug.get(slug) ?? null;
}

export function buildServicePath(
  serviceSlug: string,
  citySlug?: string,
  areaSlug?: string,
): string {
  return buildTaxonomyPath(serviceSlug, citySlug, areaSlug);
}

/// LEGACY flat slug (`tresses-cocody`) → the nested path to permanently
/// redirect to, or null.
export function parseFlatServiceLanding(
  slug: string,
  tree: LocalityTree,
): string | null {
  const svc = services.find((s) => slug.startsWith(`${s.slug}-`));
  if (!svc) return null;
  const areaSlug = slug.slice(svc.slug.length + 1);
  for (const { city, area } of allAreas(tree)) {
    if (area.slug === areaSlug) {
      return buildTaxonomyPath(svc.slug, city.slug, area.slug);
    }
  }
  return null;
}

/// Does a (free-text) service name match a taxonomy slug? (deaccented substring)
export function matchesService(serviceName: string, serviceSlug: string): boolean {
  const svc = bySlug.get(serviceSlug);
  if (!svc) return false;
  const n = normalize(serviceName);
  return svc.keywords.some((k) => n.includes(k));
}

/// All taxonomy slugs a service name maps to (a name can match several).
export function serviceSlugsForName(serviceName: string): string[] {
  const n = normalize(serviceName);
  return services
    .filter((s) => s.keywords.some((k) => n.includes(k)))
    .map((s) => s.slug);
}

/// Resolve a free-text query to a single service slug (label/slug/keyword match),
/// or null. Used by the discovery search routing.
export function serviceSlugForQuery(query: string): string | null {
  const n = normalize(query);
  if (!n) return null;
  const svc = services.find(
    (s) =>
      s.slug === slugify(query) ||
      normalize(s.label) === n ||
      s.keywords.some((k) => n.includes(k)),
  );
  return svc?.slug ?? null;
}

/// The other services at the same level (root, city or area page).
export function siblingServiceLinks(
  exceptServiceSlug: string,
  citySlug?: string,
  areaSlug?: string,
): { href: string; label: string }[] {
  return services
    .filter((s) => s.slug !== exceptServiceSlug)
    .map((s) => ({
      href: buildTaxonomyPath(s.slug, citySlug, areaSlug),
      label: s.label,
    }));
}
