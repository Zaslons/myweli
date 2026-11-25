import { buildFailsClosed } from './build-posture';

/// A salon's page works the moment it is public: the « live fallback ».
/// Design: docs/design/web-salon-page-live-fallback.md.
///
/// `app/[slug]` builds its salons ahead of time and closes its params
/// (`dynamicParams = false`), which is what gives an unknown slug a real 404
/// page instead of a blank one (served-html.spec.ts). A salon that becomes
/// public after the build therefore 404'd until the rebuild the backend asks
/// Vercel for went live: measured 2026-11-25, still 404 2 min 42 s after the
/// hook and 200 at 4 min 46 s, while search already listed it. `middleware.ts`
/// closes that window with what is below.

/// The shape the backend gives a salon slug (`slugifySalonName`,
/// backend/lib/src/providers_repository.dart): lowercase letters and digits,
/// single hyphens between them. The middleware's matcher already keeps out
/// dots, capitals and extra segments; this also refuses an edge or doubled
/// hyphen.
export const SALON_SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/// Where a public salon that is not yet built is rendered. The browser never
/// sees this path: the middleware rewrites to it, and rewrites any request
/// that names it to [NOWHERE], so the live page has no address of its own.
/// Under `recherche`, which the backend already reserves (`reservedPublicSlugs`).
export const LIVE_ROUTE_PREFIX = '/recherche/salon/';

/// Four segments: no route of the site matches it, so Vercel serves the
/// prerendered 404, the real page (served-html.spec.ts's control is the same
/// idea). Never a single segment, which `[slug]` would take.
export const NOWHERE = '/salon/introuvable/sans/adresse';

/// Set on a salon page served by the fallback. The daily production check
/// (tool/check-salon-pages.mjs) reads it: a public salon still served live long
/// after it went public means its rebuild failed or never fired.
export const LIVE_HEADER = 'x-myweli-salon-page';

/// How long the middleware waits for the API before giving up and serving the
/// 404 the site served before this existed.
export const ASK_TIMEOUT_MS = 2000;

function parseList(raw: string | undefined): string[] | null {
  if (!raw) return null;
  try {
    const value: unknown = JSON.parse(raw);
    return Array.isArray(value) && value.every((s) => typeof s === 'string')
      ? (value as string[])
      : null;
  } catch {
    return null;
  }
}

/// The salons this build prerenders, inlined by `next.config.mjs` from the
/// prebuild's one read (tool/build-salon-slugs.mjs). `null` when no list was
/// inlined. Written as a literal `process.env.X` on purpose: Next only inlines
/// that exact form.
export function inlinedSalonSlugs(): string[] | null {
  return parseList(process.env.MYWELI_BUILT_SALON_SLUGS);
}

/// The first path segment of every route of `app/` (tool/salon-build-list.mjs).
export function inlinedTopLevelRoutes(): string[] {
  return parseList(process.env.MYWELI_TOP_LEVEL_ROUTES) ?? [];
}

/// The salon slugs `app/[slug]`'s `generateStaticParams` builds.
///
/// No inlined list is normal in `next dev` (no prebuild: every salon is served
/// live) and in tests. In a production build where the build fails closed it is
/// refused: a `next build` run without its prebuild would otherwise ship with no
/// salon built, every salon page served live at two API reads a view, and
/// nothing in any log.
export function staticSalonSlugs(
  env: Record<string, string | undefined> = process.env,
): string[] {
  const list = inlinedSalonSlugs();
  if (list) return list;
  if (env.NODE_ENV === 'production' && buildFailsClosed(env)) {
    throw new Error(
      'No salon list was inlined: the prebuild (tool/build-salon-slugs.mjs) did not run. ' +
        'Build with `npm run build`, not `next build`.',
    );
  }
  return [];
}

export type SalonLists = {
  /// Slugs this build prerenders.
  built: ReadonlySet<string>;
  /// First segments the site's own routes own (`cgu`, `recherche`, `pro`…).
  routes: ReadonlySet<string>;
  /// The taxonomy roots `app/[slug]` renders (`coiffure`, `tresses`…).
  roots: ReadonlySet<string>;
};

export type Decision =
  /// Not the fallback's business: Next routes it as it always did.
  | { kind: 'pass' }
  /// The live route's own path, asked for directly: it has no address.
  | { kind: 'hide' }
  /// A salon-shaped slug the build does not know: ask the API.
  | { kind: 'ask'; slug: string };

/// What the middleware does with a path, before any network call. Only an
/// unknown salon-shaped slug ever costs an API read: a built salon, a route of
/// the site and a taxonomy root never do.
export function decide(pathname: string, lists: SalonLists): Decision {
  if (pathname === LIVE_ROUTE_PREFIX.slice(0, -1) || pathname.startsWith(LIVE_ROUTE_PREFIX)) {
    return { kind: 'hide' };
  }
  const match = /^\/([^/]+)$/.exec(pathname);
  if (!match) return { kind: 'pass' };
  const slug = match[1];
  if (!SALON_SLUG.test(slug)) return { kind: 'pass' };
  if (lists.built.has(slug) || lists.routes.has(slug) || lists.roots.has(slug)) {
    return { kind: 'pass' };
  }
  return { kind: 'ask', slug };
}

export type Route =
  | { kind: 'pass' }
  | { kind: 'rewrite'; pathname: string; live: boolean };

/// The whole fallback, with the API read injected. [isPublic] answers `true`
/// only for a salon the API serves as public; any failure is `false`, never a
/// throw, so the worst case is the 404 the site served before.
export async function route(
  pathname: string,
  lists: SalonLists,
  isPublic: (slug: string) => Promise<boolean>,
): Promise<Route> {
  const decision = decide(pathname, lists);
  if (decision.kind === 'hide') return { kind: 'rewrite', pathname: NOWHERE, live: false };
  if (decision.kind === 'pass') return { kind: 'pass' };
  let ok = false;
  try {
    ok = await isPublic(decision.slug);
  } catch {
    ok = false;
  }
  return ok
    ? { kind: 'rewrite', pathname: `${LIVE_ROUTE_PREFIX}${decision.slug}`, live: true }
    : { kind: 'pass' };
}
