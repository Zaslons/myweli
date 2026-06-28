import { communes } from './landing';
import { normalize, slugify } from './slug';

/// Service × commune SEO landing (e.g. /tresses-cocody). Curated taxonomy from
/// PRD Appendix A; providers are matched client-side by service name (the API
/// has no service filter). Design: docs/design/web-m4-1-service-landing.md.

export type ServiceLanding = {
  serviceSlug: string;
  label: string;
  commune: string;
};

const services: { slug: string; label: string; keywords: string[] }[] = [
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
const communeBySlug = new Map(communes.map((c) => [slugify(c), c]));

export function buildServiceLandingSlug(
  serviceSlug: string,
  commune: string,
): string {
  return `${serviceSlug}-${slugify(commune)}`;
}

export function parseServiceLanding(slug: string): ServiceLanding | null {
  const svc = services.find((s) => slug.startsWith(`${s.slug}-`));
  if (!svc) return null;
  const commune = communeBySlug.get(slug.slice(svc.slug.length + 1));
  if (!commune) return null;
  return { serviceSlug: svc.slug, label: svc.label, commune };
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

export function siblingCommunesForService(
  serviceSlug: string,
  exceptCommune: string,
): { slug: string; commune: string }[] {
  return communes
    .filter((c) => c !== exceptCommune)
    .map((c) => ({ slug: buildServiceLandingSlug(serviceSlug, c), commune: c }));
}

export function siblingServicesForCommune(
  commune: string,
  exceptServiceSlug: string,
): { slug: string; label: string }[] {
  return services
    .filter((s) => s.slug !== exceptServiceSlug)
    .map((s) => ({
      slug: buildServiceLandingSlug(s.slug, commune),
      label: s.label,
    }));
}
