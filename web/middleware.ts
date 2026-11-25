import { NextResponse, type NextRequest } from 'next/server';
import { api } from './lib/api/client';
import {
  ASK_TIMEOUT_MS,
  LIVE_HEADER,
  inlinedSalonSlugs,
  inlinedTopLevelRoutes,
  route,
  type SalonLists,
} from './lib/salon-fallback';
import { taxonomyRootSlugs } from './lib/taxonomy';

/// The « live fallback »: a salon that is public but not yet in this build is
/// served live at its own address, instead of the 404 it got until the rebuild
/// went live. Everything else is routed exactly as before.
/// Design: docs/design/web-salon-page-live-fallback.md §3.2.
///
/// **The matcher carries its own pattern, on purpose.** Next 14.2 appends
/// `(.json)?` to every source, so a bare `'/:slug'` compiles to a parameter
/// whose pattern IS `.json`, and never matches `/test-3` (measured in a probe
/// build). `[a-z0-9-]+` also keeps dotted files (`/favicon.ico`) and capitals out
/// of the middleware entirely. The second entry is the live route's own path:
/// without it a three-segment request never enters the middleware, and the live
/// page would answer anyone who typed its address.
/// `tests/salon-fallback.test.ts` compiles this matcher with Next's own code.
export const config = {
  matcher: ['/:slug([a-z0-9-]+)', '/recherche/salon/:path*'],
};

const lists: SalonLists = {
  built: new Set(inlinedSalonSlugs() ?? []),
  routes: new Set(inlinedTopLevelRoutes()),
  roots: new Set(taxonomyRootSlugs()),
};

/// One read of the public salon. `true` only for a 200 that carries a salon;
/// a 404, any other status, a timeout or a network error is `false`. It never
/// throws and logs nothing: an unknown slug is whatever a visitor typed.
async function isPublicSalon(slug: string): Promise<boolean> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ASK_TIMEOUT_MS);
  try {
    const { data, response } = await api.GET('/providers/by-slug/{slug}', {
      params: { path: { slug } },
      signal: controller.signal,
    });
    return response.status === 200 && typeof data?.id === 'string';
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

export async function middleware(request: NextRequest): Promise<NextResponse> {
  const outcome = await route(request.nextUrl.pathname, lists, isPublicSalon);
  if (outcome.kind === 'pass') return NextResponse.next();
  // Clone, so the query survives the rewrite: a client navigation's `_rsc`
  // request carries one.
  const target = request.nextUrl.clone();
  target.pathname = outcome.pathname;
  return NextResponse.rewrite(
    target,
    outcome.live ? { headers: { [LIVE_HEADER]: 'live' } } : undefined,
  );
}
