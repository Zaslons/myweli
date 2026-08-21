import type { LocalityTree } from './api/localities';
import { taxonomyRootSlugs } from './taxonomy';

/// The complete set of nested landing pages, derived from the **locality tree**.
///
/// **One derivation, used by both the sitemap and `generateStaticParams`.**
/// They disagreed. The sitemap was fixed on 2026-08-20 to derive the commune
/// level from the tree — that is where the "187 live pages nobody listed"
/// finding came from — but the route's own `generateStaticParams` still asked
/// the *catalogue* ("combos present in the live catalogue"), which is empty
/// until a salon opens. So the sitemap advertised 187 URLs the build did not
/// prebuild, and the two could drift apart again independently.
///
/// The tree knows every commune whether or not a salon has opened there, and a
/// landing page for an empty commune is exactly the page a crawler should find
/// first — it is how the first salon in that commune gets discovered.
///
/// **This is now load-bearing for correctness, not just for SEO.** Both landing
/// routes set `dynamicParams = false`, so an entry missing from here is a page
/// that 404s. That is the trade being made deliberately: the space is finite
/// and fully known at build time, and in exchange an unknown city or commune
/// never enters the route at all — which is the only way Next 14 serves a real
/// 404 in the HTML rather than a 44-character `__next_error__` shell.
/// **Refuses to return an empty set, and that is deliberate.**
///
/// `getLocalityTree()` swallows a failed fetch and returns `emptyTree`. With
/// `dynamicParams = false` downstream, an empty result does not degrade — it
/// makes EVERY city and commune page 404, sitewide, from one transient API
/// blip at build time. Failing the build instead turns a silent catastrophe
/// into a loud, obvious one, the same trade `lib/api-base.ts` makes when
/// `API_BASE_URL` is unset.
function assertNonEmpty<T>(params: T[], level: string): T[] {
  if (params.length === 0) {
    throw new Error(
      `The locality tree yielded no ${level} params. Refusing to build: with `
        + 'dynamicParams=false this would 404 every landing page on the site. '
        + 'Check that the API is reachable from the build.',
    );
  }
  return params;
}

export function taxonomyCityParams(
  tree: LocalityTree,
): { slug: string; city: string }[] {
  const cities = tree.countries.flatMap((c) => c.cities.map((x) => x.slug));
  return assertNonEmpty(
    taxonomyRootSlugs().flatMap((slug) => cities.map((city) => ({ slug, city }))),
    'city',
  );
}

export function taxonomyAreaParams(
  tree: LocalityTree,
): { slug: string; city: string; area: string }[] {
  const cityAreas = tree.countries.flatMap((c) =>
    c.cities.flatMap((city) =>
      (city.areas ?? []).map((area) => [city.slug, area.slug] as const),
    ),
  );
  return assertNonEmpty(
    taxonomyRootSlugs().flatMap((slug) =>
      cityAreas.map(([city, area]) => ({ slug, city, area })),
    ),
    'commune',
  );
}
