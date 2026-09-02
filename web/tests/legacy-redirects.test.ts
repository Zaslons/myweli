import { afterEach, describe, expect, it } from 'vitest';
// @ts-expect-error — next.config.mjs is plain ESM with no declaration file.
// Its RUNTIME value is precisely what this test exists to compare.
import { TAXONOMY_ROOTS, redirectsFailClosed } from '../next.config.mjs';
import { buildFailsClosed } from '../lib/build-posture';
import { taxonomyCityParams } from '../lib/taxonomyParams';
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

describe('the redirect fetch fails CLOSED exactly where it must', () => {
  // The pre-launch economy put the staging DB to sleep, and the first
  // preview after that died on GET /localities -> 500 — every PR's Vercel
  // check red. Previews may build degraded; production may not.
  it('production (and local/CI builds) keep the hard fail', () => {
    expect(redirectsFailClosed({ VERCEL_ENV: 'production' })).toBe(true);
    expect(redirectsFailClosed({})).toBe(true); // no VERCEL_ENV = local/CI
  });

  it('previews build without redirects rather than turning every PR red', () => {
    expect(redirectsFailClosed({ VERCEL_ENV: 'preview' })).toBe(false);
    expect(redirectsFailClosed({ VERCEL_ENV: 'development' })).toBe(false);
  });
});

describe('the two fail-closed predicates cannot drift', () => {
  // next.config.mjs cannot import TypeScript, so the predicate exists twice
  // (redirectsFailClosed there, buildFailsClosed in lib). Same answers on
  // every shape, or previews and redirects disagree about what a preview is.
  it('agree on every posture', () => {
    for (const env of [
      {},
      { VERCEL_ENV: 'production' },
      { VERCEL_ENV: 'preview' },
      { VERCEL_ENV: 'development' },
    ]) {
      expect(buildFailsClosed(env)).toBe(redirectsFailClosed(env));
    }
  });
});

describe('assertNonEmpty is WIRED to the posture, not just documented', () => {
  const emptyTree = { countries: [] };
  const saved = process.env.VERCEL_ENV;
  afterEach(() => {
    if (saved === undefined) delete process.env.VERCEL_ENV;
    else process.env.VERCEL_ENV = saved;
  });

  it('a preview degrades an empty tree to zero pages', () => {
    process.env.VERCEL_ENV = 'preview';
    expect(taxonomyCityParams(emptyTree as never)).toEqual([]);
  });

  it('production refuses the same empty tree', () => {
    process.env.VERCEL_ENV = 'production';
    expect(() => taxonomyCityParams(emptyTree as never)).toThrow(/Refusing to build/);
  });
});
