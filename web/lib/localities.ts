import type { components } from './api/schema';

/// The locality tree's TYPES and PURE LOOKUPS — no network, no API client.
///
/// **Split out of `lib/api/localities.ts` on 2026-08-18, and the reason is the
/// import graph, not tidiness.** Six `'use client'` modules import `allAreas`,
/// `defaultCity` and friends. They are pure functions, but they used to live
/// beside `getLocalityTree`, which imports `./api/client` — so every one of
/// those client bundles carried the openapi-fetch client and the API base URL
/// inlined, for functions that never make a request. Measured: the base URL
/// shipped in four production chunks with its `createClient()` return value
/// discarded, never bound.
///
/// That was harmless and load-bearing at the same time. Harmless because
/// nothing called it; load-bearing because it is what made `import
/// 'server-only'` impossible in `api/client.ts` — and that guard is what lets
/// the staging backend keep a `WEB_ORIGINS` allowlist with no Vercel preview
/// origins in it. See docs/LAUNCH.md §5.4.
///
/// Rule: **anything a client component needs goes here; anything that fetches
/// stays in `lib/api/`.**

export type LocalityTree = components['schemas']['LocalityTree'];
export type LocalityCountry = components['schemas']['LocalityCountry'];
export type LocalityCity = components['schemas']['LocalityCity'];
export type LocalityArea = components['schemas']['LocalityArea'];
export type MomoOperator = components['schemas']['MomoOperator'];

export const emptyTree: LocalityTree = { countries: [] };

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
