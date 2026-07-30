import { api } from './client';
import type { components } from './schema';

/// The locality tree (multi-pays MP3 — docs/design/multi-pays-end-version.md
/// §6): country → city → area + the per-country Mobile-Money operator
/// catalog. THE source of web geography — the hardcoded commune list is gone.
/// Server components call `getLocalityTree()` (page-level ISR governs
/// freshness); client components go through `/api/localities` +
/// `lib/use-localities.ts`.

export type LocalityTree = components['schemas']['LocalityTree'];
export type LocalityCountry = components['schemas']['LocalityCountry'];
export type LocalityCity = components['schemas']['LocalityCity'];
export type LocalityArea = components['schemas']['LocalityArea'];
export type MomoOperator = components['schemas']['MomoOperator'];

export const emptyTree: LocalityTree = { countries: [] };

/// Fetch the tree; empty tree on any failure so SSG/ISR builds never crash
/// (the getLandingSlugs idiom). Module-cached per server process — the
/// endpoint is public, parameterless and CDN-cacheable (T56).
let cached: Promise<LocalityTree> | null = null;

export async function getLocalityTree(): Promise<LocalityTree> {
  cached ??= (async () => {
    try {
      const { data, error } = await api.GET('/localities', {});
      if (error || !data) return emptyTree;
      return data;
    } catch {
      return emptyTree;
    }
  })().then((tree) => {
    // Never pin a failed fetch for the process lifetime.
    if (tree.countries.length === 0) cached = null;
    return tree;
  });
  return cached;
}

/// Test seam: reset the module cache.
export function resetLocalityCache(): void {
  cached = null;
}

// ---------------------------------------------------------------------------
// Pure lookups (shared by server pages, taxonomy libs and client hooks).

/// The home market — the first seeded country (CI in Wave 0).
export function defaultCountry(tree: LocalityTree): LocalityCountry | null {
  return tree.countries[0] ?? null;
}

/// The default country's first city (Abidjan in Wave 0) — home-page copy,
/// directory and search suggestions center on it.
export function defaultCity(tree: LocalityTree): LocalityCity | null {
  return defaultCountry(tree)?.cities[0] ?? null;
}

export function findCity(
  tree: LocalityTree,
  citySlug: string,
): LocalityCity | null {
  for (const country of tree.countries) {
    const city = country.cities.find((c) => c.slug === citySlug);
    if (city) return city;
  }
  return null;
}

export function findArea(
  city: LocalityCity,
  areaSlug: string,
): LocalityArea | null {
  return city.areas.find((a) => a.slug === areaSlug) ?? null;
}

/// Every (city, area) pair in the tree — pickers, datalists, flat-slug
/// redirect recognition.
export function allAreas(
  tree: LocalityTree,
): { city: LocalityCity; area: LocalityArea }[] {
  const out: { city: LocalityCity; area: LocalityArea }[] = [];
  for (const country of tree.countries) {
    for (const city of country.cities) {
      for (const area of city.areas) out.push({ city, area });
    }
  }
  return out;
}

export function countryOf(
  tree: LocalityTree,
  code: string | null | undefined,
): LocalityCountry | null {
  if (!code) return null;
  return tree.countries.find((c) => c.code === code) ?? null;
}

/// Display name for a salon's country code (SalonTimeHint label). Null when
/// the tree misses it — callers fall back to the Wave-0 copy.
export function countryName(
  tree: LocalityTree,
  code: string | null | undefined,
): string | null {
  return countryOf(tree, code)?.name ?? null;
}

/// The Mobile-Money operator catalog for a salon's country (deposit pickers
/// + labels). Unknown/missing code → the default country's catalog.
export function operatorsFor(
  tree: LocalityTree,
  code: string | null | undefined,
): MomoOperator[] {
  return (countryOf(tree, code) ?? defaultCountry(tree))?.operators ?? [];
}
