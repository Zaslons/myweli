import { withSentryConfig } from '@sentry/nextjs';

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
