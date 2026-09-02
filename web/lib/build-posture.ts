/// Does a failed build-time fetch FAIL the build?
///
/// Production and local/CI builds: yes — shipping without the landing pages
/// or the legacy redirects would 404 real URLs sitewide, and a loud build
/// failure beats a silent catastrophe (the `taxonomyParams` reasoning).
///
/// Vercel PREVIEWS: no — they point at STAGING, whose database sleeps
/// between rehearsals (pre-launch economy, DEPLOYMENT.md). The first preview
/// after that change died in `next.config.mjs` on `GET /localities -> 500`,
/// turning the Vercel check red on every PR. A preview that builds degraded
/// (no landing pages, no redirects) is honest; a red check on every PR
/// normalises red.
///
/// `next.config.mjs` carries its own copy (`redirectsFailClosed`) because
/// `.mjs` cannot import TypeScript; `legacy-redirects.test.ts` pins the two
/// against each other so they cannot drift.
export function buildFailsClosed(
  env: Record<string, string | undefined> = process.env,
): boolean {
  return env.VERCEL_ENV === 'production' || !env.VERCEL_ENV;
}
