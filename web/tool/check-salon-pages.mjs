/// Daily, on the real domain: is every salon the API lists as public served by
/// the BUILD on myweli.com? Design: docs/design/web-salon-page-live-fallback.md §8.3.
///
/// **What it catches that nothing else does.** The backend asks Vercel for a
/// rebuild whenever the public set changes, and alerts when Vercel REFUSES the
/// hook (`site_rebuild FAILED`). A hook Vercel accepts (201) whose build then
/// fails, or a hook that never fires, is silent. Before the live fallback it
/// meant a salon page answering « Page introuvable » until the next deploy;
/// since, the visitor gets the page, served live, so nobody would ever notice
/// the static set falling behind. This notices.
///
/// A salon served live (`x-myweli-salon-page: live`) or answering 404 is checked
/// again 10 minutes later: one validated just before the run is
/// inside its build window, not a fault. Still not static then: red, naming it.
///
/// Plain `fetch`, no dependency, no browser. `tests/check-salon-pages.test.ts`
/// holds the decision and the retry.

import { pathToFileURL } from 'node:url';

export const LIVE_HEADER = 'x-myweli-salon-page';

/// One salon page's answer, read: `static` is the only good one.
export function verdict({ status, live }) {
  if (status === 200) return live ? 'live' : 'static';
  if (status === 404) return 'missing';
  return 'error';
}

export async function publicSlugs({ api, fetchImpl = fetch }) {
  const res = await fetchImpl(`${api.replace(/\/+$/, '')}/sitemap/providers`, {
    headers: { accept: 'application/json' },
  });
  if (!res.ok) throw new Error(`GET /sitemap/providers answered ${res.status}`);
  const body = await res.json();
  if (!Array.isArray(body?.items)) throw new Error('GET /sitemap/providers: no `items`');
  return body.items.map((i) => i?.slug).filter((s) => typeof s === 'string');
}

export async function readPage({ site, slug, fetchImpl = fetch }) {
  const res = await fetchImpl(`${site.replace(/\/+$/, '')}/${slug}`, { redirect: 'manual' });
  return verdict({ status: res.status, live: res.headers.get(LIVE_HEADER) === 'live' });
}

/// The whole check. Returns the slugs still not static after the retry, with
/// what they answered.
export async function check({
  api,
  site,
  fetchImpl = fetch,
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
  retryAfterMs = 10 * 60 * 1000,
  log = console.log,
}) {
  const slugs = await publicSlugs({ api, fetchImpl });
  log(`${slugs.length} public salon(s) listed by the API`);
  const first = [];
  for (const slug of slugs) {
    const v = await readPage({ site, slug, fetchImpl });
    log(`  /${slug}: ${v}`);
    if (v !== 'static') first.push(slug);
  }
  if (first.length === 0) return [];
  log(`${first.length} not served by the build; checking again in ${retryAfterMs / 60000} min`);
  await sleep(retryAfterMs);
  const failures = [];
  for (const slug of first) {
    const v = await readPage({ site, slug, fetchImpl });
    log(`  /${slug}, again: ${v}`);
    if (v !== 'static') failures.push({ slug, verdict: v });
  }
  return failures;
}

// `pathToFileURL`, not a hand-built `file://` string: the latter never equals
// `import.meta.url` in a path with a space (« beauty app » → `%20`), and the
// check then exits 0 without checking anything. Watched happening.
const isMain = process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url;
if (isMain) {
  const site = process.env.TARGET?.trim() || 'https://myweli.com';
  const api = process.env.API_BASE?.trim() || 'https://api.myweli.com';
  try {
    const failures = await check({ api, site });
    if (failures.length > 0) {
      for (const f of failures) {
        console.error(
          `::error::${site}/${f.slug} is public in the API and ${f.verdict === 'live' ? 'served live, not by the build' : `answers « ${f.verdict} »`}: its rebuild failed or never fired (docs/design/web-salon-page-live-fallback.md §8.3).`,
        );
      }
      process.exit(1);
    }
    console.log('every public salon is served by the build');
  } catch (e) {
    console.error(`::error::the check could not run: ${e instanceof Error ? e.message : String(e)}`);
    process.exit(1);
  }
}
