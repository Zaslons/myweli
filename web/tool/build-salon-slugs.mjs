/// The prebuild's salon list: one read of `GET /sitemap/providers`, written to
/// `.generated/salon-slugs.json` for `next.config.mjs` to inline.
/// Design: docs/design/web-salon-page-live-fallback.md §3.1.
///
/// **Env the way Next loads it.** A plain `node` script does not read
/// `.env.local`; `next build` does. Without `loadEnvConfig`, a local build whose
/// API base lives only in `.env.local` would fail here for no reason.
///
/// **The base is required,** as it is for `next build` itself
/// (`lib/api-base.ts`: production never falls back to localhost).
// CommonJS: a named ESM import of it fails at load (« Named export not found »).
import nextEnv from '@next/env';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SALON_LIST_FILE, fetchSalonSlugs, failsClosed } from './salon-build-list.mjs';

nextEnv.loadEnvConfig(resolve(dirname(fileURLToPath(import.meta.url)), '..'), false, {
  info: () => {},
  error: console.error,
});

const base = process.env.NEXT_PUBLIC_API_BASE_URL?.trim();
if (!base) {
  console.error(
    '::error::NEXT_PUBLIC_API_BASE_URL is not set: the salon list cannot be read, ' +
      'and `next build` would refuse to fall back to localhost anyway.',
  );
  process.exit(1);
}

let slugs;
try {
  slugs = await fetchSalonSlugs({ base });
} catch (e) {
  console.error(`::error::${e instanceof Error ? e.message : String(e)}`);
  process.exit(1);
}

await mkdir(dirname(SALON_LIST_FILE), { recursive: true });
await writeFile(
  SALON_LIST_FILE,
  `${JSON.stringify({ slugs, readAt: new Date().toISOString() }, null, 2)}\n`,
);
console.log(
  `salon list: ${slugs.length} salon(s) built statically` +
    (slugs.length === 0 && !failsClosed() ? ' (preview: every salon is served live)' : ''),
);
