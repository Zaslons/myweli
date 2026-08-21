import { withSentryConfig } from '@sentry/nextjs';

/// The 17 SEO taxonomy roots (5 categories + 13 services, `massage` overlapping), duplicated from `lib/taxonomy.ts` because a
/// `.mjs` config cannot import TypeScript. `tests/legacy-redirects.test.ts`
/// fails if the two lists ever disagree — the same "two halves of a contract,
/// pinned by a test" shape `legal.test.tsx` uses for the mobile slug contract.
export const TAXONOMY_ROOTS = [
  'coiffure',
  'barbier',
  'onglerie',
  'spa',
  'massage',
  'tresses',
  'tissage',
  'defrisage',
  'coupe-homme',
  'barbe',
  'coupe-femme',
  'locks',
  'coloration',
  'manucure',
  'pedicure',
  'ongles',
  'soin-visage',
];

/// **The legacy flat landings (`/coiffure-cocody`) 308 from HERE, not from a
/// page.** They used to redirect inside `app/[slug]/page.tsx`. That stopped
/// working the moment that route closed its params: a PRERENDERED redirect
/// answers 308 with **no `Location` header at all** — the redirect lives in the
/// RSC payload, exactly like the 404 shell this whole change is about, and
/// `redirects.spec.ts` caught it. A config redirect is a real HTTP redirect,
/// resolved before routing, so it is immune to that.
///
/// The tree is fetched at build. If it comes back empty the build FAILS rather
/// than silently shipping a site where every legacy URL 404s.
async function legacyFlatRedirects() {
  const base =
    process.env.API_BASE_URL ?? process.env.NEXT_PUBLIC_API_BASE_URL ?? '';
  if (!base) {
    throw new Error(
      'No API base URL: cannot build the legacy flat redirects. '
        + 'Set NEXT_PUBLIC_API_BASE_URL.',
    );
  }
  const res = await fetch(`${base}/localities`);
  if (!res.ok) throw new Error(`GET /localities -> ${res.status}`);
  const tree = await res.json();
  const pairs = (tree.countries ?? []).flatMap((c) =>
    (c.cities ?? []).flatMap((city) =>
      (city.areas ?? []).map((area) => [city.slug, area.slug]),
    ),
  );
  if (pairs.length === 0) {
    throw new Error(
      'The locality tree yielded no areas. Refusing to build: every legacy '
        + 'flat URL would 404.',
    );
  }
  return TAXONOMY_ROOTS.flatMap((root) =>
    pairs.map(([city, area]) => ({
      source: `/${root}-${area}`,
      destination: `/${root}/${city}/${area}`,
      permanent: true,
    })),
  );
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  env: {
    // Vercel sets VERCEL_GIT_COMMIT_SHA on every build; exposing it as
    // NEXT_PUBLIC_RELEASE is what makes Sentry's release health work without
    // anyone having to set a variable per deploy — which nobody would do
    // reliably, so "release" would end up undefined and every error would group
    // under "no release". Empty string locally, which the SDK treats as unset.
    NEXT_PUBLIC_RELEASE:
      process.env.NEXT_PUBLIC_RELEASE ?? process.env.VERCEL_GIT_COMMIT_SHA ?? '',
  },
  async redirects() {
    return legacyFlatRedirects();
  },
  experimental: {
    // Required on Next 14 for `instrumentation.ts` to run at all (stable in 15).
    // Without it the Sentry server/edge init is a file nobody imports.
    instrumentationHook: true,
  },
  images: {
    // Hosts allowed for next/image. Salon photos come from the R2 public bucket
    // (R2_PUBLIC_BASE_URL = https://cdn.myweli.com at deploy); the R2 default
    // endpoint and the hermetic e2e stub host are allowed too.
    remotePatterns: [
      { protocol: 'https', hostname: 'cdn.myweli.com' },
      { protocol: 'https', hostname: '**.r2.cloudflarestorage.com' },
      { protocol: 'https', hostname: 'cdn.stub' }, // e2e stub images
    ],
  },
};

/// `withSentryConfig` is what loads `sentry.client.config.ts` and wires the
/// build. Without it the SDK config files are inert — the build stays green and
/// nothing is ever reported, which is the failure this whole slice exists to
/// prevent.
///
/// Source-map upload is skipped when `SENTRY_AUTH_TOKEN` is unset, so a
/// developer or CI without Sentry credentials still builds. Stack traces are
/// then minified until the token is configured — noted rather than hidden.
export default withSentryConfig(nextConfig, {
  silent: true,
  // Do not fail a build because telemetry could not be uploaded.
  errorHandler: () => {},
});
