/// The salon list a build serves statically, and the site's own top-level routes:
/// the two lists the salon page and `middleware.ts` share.
/// Design: docs/design/web-salon-page-live-fallback.md §3.1.
///
/// Plain `.mjs` because `next.config.mjs` and the prebuild script both read it,
/// and neither can import TypeScript. `tests/salon-build-list.test.ts` holds the
/// copies below to their TypeScript originals.
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/// Written by `tool/build-salon-slugs.mjs` (the prebuild), read by
/// `next.config.mjs`. Gitignored: regenerated on every build, like the flags.
export const SALON_LIST_FILE = resolve(webRoot, '.generated/salon-slugs.json');

/// A copy of `buildFailsClosed` (lib/build-posture.ts): production, local and CI
/// fail closed; a Vercel preview, whose staging API sleeps, degrades.
export function failsClosed(env = process.env) {
  return env.VERCEL_ENV === 'production' || !env.VERCEL_ENV;
}

/// ONE read of `GET /sitemap/providers`. **Why one:** the middleware passes a slug
/// it believes is built WITHOUT asking the API. A second read, seconds later,
/// could list a salon the first did not, or the reverse, and a slug the
/// middleware believes built but the page did not build gets the old 404 with no
/// fallback.
///
/// Fails like the page's own read did (`lib/api/public-read.ts`): where the build
/// fails closed it throws, so the build fails and the last deployment stays up;
/// on a preview it returns an empty list, and every preview salon is served live.
export async function fetchSalonSlugs({ base, fetchImpl = fetch, env = process.env }) {
  let cause;
  try {
    const res = await fetchImpl(`${base.replace(/\/+$/, '')}/sitemap/providers`, {
      headers: { accept: 'application/json' },
    });
    if (res.ok) {
      const body = await res.json();
      if (Array.isArray(body?.items)) {
        // As `getAllProviderSlugs` did: every string slug, nothing else checked.
        const slugs = body.items.map((i) => i?.slug).filter((s) => typeof s === 'string');
        return [...new Set(slugs)].sort();
      } else {
        cause = 'a 200 without `items`';
      }
    } else {
      cause = `status ${res.status}`;
    }
  } catch (e) {
    cause = e instanceof Error ? e.message : String(e);
  }
  if (!failsClosed(env)) return [];
  throw new Error(
    `GET /sitemap/providers could not be read (${cause}). Not building the salon pages from an empty list.`,
  );
}

/// The file's slugs, or `null` when there is no file (`next dev`, a test, a
/// `next build` run without its prebuild). A file that exists and does not parse
/// is an error: it can only be a broken prebuild.
export function readSalonListFile(file = SALON_LIST_FILE) {
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') return null;
    throw e;
  }
  const parsed = JSON.parse(text);
  if (!Array.isArray(parsed?.slugs) || parsed.slugs.some((s) => typeof s !== 'string')) {
    throw new Error(`${file} has no \`slugs\` list. Rerun the prebuild.`);
  }
  return parsed.slugs;
}

/// Every first path segment a route of `app/` owns: each folder that is not
/// dynamic (`[slug]`), private (`_x`) or a parallel slot (`@x`). A route group
/// (`(x)`) adds no segment, so its children are read instead. The middleware
/// never asks the API about these, so a new page can never cost an API read per
/// view. `tests/e2e/salon-live-fallback.spec.ts` holds this list to Next's own
/// build output.
export function topLevelRoutes(appDir = resolve(webRoot, 'app')) {
  const out = new Set();
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const name = entry.name;
      if (name.startsWith('(') && name.endsWith(')')) {
        walk(resolve(dir, name));
        continue;
      }
      if (name.startsWith('[') || name.startsWith('_') || name.startsWith('@')) continue;
      out.add(name);
    }
  };
  walk(appDir);
  return [...out].sort();
}
