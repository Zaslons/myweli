import { describe, expect, it } from 'vitest';
// @ts-expect-error — next.config.mjs is plain ESM with no declaration file.
// Its RUNTIME value is precisely what this test exists to compare.
import { TAXONOMY_ROOTS } from '../next.config.mjs';
import { taxonomyRootSlugs } from '../lib/taxonomy';

/// **Two halves of one contract**, the shape `legal.test.tsx` already uses for
/// the mobile slug list.
///
/// The legacy flat landings (`/coiffure-cocody`) 308 from `next.config.mjs`,
/// which is `.mjs` and cannot import TypeScript — so the root list is written
/// out there by hand. If it drifts from `taxonomyRootSlugs()`, some legacy URLs
/// silently stop redirecting and start 404ing, and nothing else would notice:
/// the redirect is generated at build from whatever that array happens to say.
///
/// Watched red: the first version of that array was written from the design
/// doc's "5 categories + 13 curated services" and had **18** entries, several
/// of them slugs that do not exist. The real list is 17 — `massage` is both a
/// category and a service, and is deduplicated.
describe('the legacy-redirect root list matches the taxonomy', () => {
  it('is exactly taxonomyRootSlugs(), same members', () => {
    expect([...TAXONOMY_ROOTS].sort()).toEqual([...taxonomyRootSlugs()].sort());
  });

  it('has no duplicates — a duplicate becomes a duplicate redirect source', () => {
    expect(new Set(TAXONOMY_ROOTS).size).toBe(TAXONOMY_ROOTS.length);
  });
});
