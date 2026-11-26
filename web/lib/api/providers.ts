import { appendNew, RECHERCHE_PAGE_SIZE } from '../discovery/search-pages';
import { categorySlugForApiKey } from '../landing';
import { serviceSlugsForName } from '../service-landing';
import { slugify } from '../slug';
import { api } from './client';
import { allAreas, type LocalityTree } from './localities';
import { unreadable } from './public-read';
import type { components } from './schema';

export type Provider = components['schemas']['Provider'];
export type Service = components['schemas']['Service'];
export type Review = components['schemas']['Review'];
export type Artist = components['schemas']['Artist'];

/// Public provider read by slug (web M1 endpoint). `null` for a real 404 only,
/// so the page can `notFound()`. Any other failure is [unreadable]: it used to
/// be `null` too, so a 30-second API blip cached a 404 for a LIVE salon for the
/// whole ISR window.
export async function getProviderBySlug(slug: string): Promise<Provider | null> {
  let cause: unknown;
  try {
    const { data, error, response } = await api.GET('/providers/by-slug/{slug}', {
      params: { path: { slug } },
    });
    if (typeof data?.id === 'string') return data;
    if (response.status === 404) return null;
    cause = error ?? `status ${response.status}, no salon`;
  } catch (e) {
    cause = e;
  }
  return unreadable(`GET /providers/by-slug/${slug}`, null, cause);
}

/// A list read: the answer's `items`, or [unreadable]. A real empty list is
/// an empty list.
async function readItems<T>(
  what: string,
  call: () => Promise<{ data?: { items?: T[] }; error?: unknown }>,
): Promise<T[]> {
  let cause: unknown;
  try {
    const { data, error } = await call();
    if (!error && Array.isArray(data?.items)) return data.items;
    cause = error ?? 'no items';
  } catch (e) {
    cause = e;
  }
  return unreadable(what, [] as T[], cause);
}

/// All listable provider slugs (for generateStaticParams + the sitemap).
export async function getAllProviderSlugs(): Promise<string[]> {
  const items = await readItems('GET /sitemap/providers', () =>
    api.GET('/sitemap/providers', {}),
  );
  return items
    .map((i) => i.slug)
    .filter((s): s is string => typeof s === 'string');
}

/// Providers in a category + commune, best-rated first (backs a landing page).
export async function listProviders(
  apiKey: string,
  commune: string,
): Promise<Provider[]> {
  return readItems('GET /providers (landing)', () =>
    api.GET('/providers', {
      params: { query: { category: apiKey, commune, sort: 'rating' } },
    }),
  );
}

/// Flexible discovery search/list (home featured + /recherche). Any of q /
/// category / commune; sorted by rating; bounded.
export async function searchProviders(opts: {
  q?: string;
  category?: string;
  commune?: string;
  pageSize?: number;
  /// FR-DISC-007 (parity 2.1/2.2): /recherche passes the user's choice;
  /// home/landing callers keep the default rating order.
  sort?: 'relevance' | 'rating' | 'price';
  availableToday?: boolean;
}): Promise<Provider[]> {
  return readItems('GET /providers (search)', () =>
    api.GET('/providers', {
      params: {
        query: {
          ...(opts.q ? { q: opts.q } : {}),
          ...(opts.category ? { category: opts.category } : {}),
          ...(opts.commune ? { commune: opts.commune } : {}),
          ...(opts.availableToday ? { availableToday: true } : {}),
          sort: opts.sort ?? 'rating',
          pageSize: opts.pageSize ?? 12,
        },
      },
    }),
  );
}

/// `/recherche`'s rows (docs/design/consumer-search.md §3.3, A4w): page 1, then pages 2 to
/// [pages] of [RECHERCHE_PAGE_SIZE] in parallel — never past the last page page 1's `total`
/// says exists, since each read loads, and with « Disponible aujourd’hui » checks, every
/// matching salon: a typed `pages=10` over 20 salons is one read, not ten. The rows are
/// de-duplicated by id; the count is the newest page's `total`; [pages] comes from the
/// address, already 1 to 10 (`pagesFromParam`).
///
/// - **Page 1 that cannot be read** — a refusal, no answer, a 200 without its items **or its
///   `total`** — is [unreadable], like every public read.
/// - **A later page that cannot be read** shows the pages read before it, and says how many:
///   the address then comes down to them and « Afficher plus » offers the rest. Fewer rows
///   under the true count, with the button, is what page 1 alone already shows.
export async function searchProviderPages(
  opts: {
    q?: string;
    category?: string;
    commune?: string;
    sort?: 'relevance' | 'rating' | 'price';
    availableToday?: boolean;
  },
  pages: number,
): Promise<{ items: Provider[]; total: number; pages: number }> {
  const what = 'GET /providers (recherche)';
  const first = await readRecherchePage(opts, 1);
  if (!first.ok) {
    return unreadable(what, { items: [] as Provider[], total: 0, pages: 1 }, first.cause);
  }
  const last = Math.min(pages, Math.max(1, Math.ceil(first.total / RECHERCHE_PAGE_SIZE)));
  const rest = await Promise.all(
    Array.from({ length: last - 1 }, (_, i) => readRecherchePage(opts, i + 2)),
  );
  let items = first.items;
  let total = first.total;
  let read = 1;
  for (const r of rest) {
    if (!r.ok) {
      // No search text in the log (BACKLOG B0.15): the page numbers say enough.
      console.warn(`${what}: page ${read + 1} of ${last} could not be read; showing ${read}.`);
      break;
    }
    items = appendNew(items, r.items);
    total = r.total;
    read += 1;
  }
  return { items, total, pages: read };
}

/// One page of `/recherche`, or why it could not be read.
async function readRecherchePage(
  opts: Parameters<typeof searchProviderPages>[0],
  page: number,
): Promise<{ ok: true; items: Provider[]; total: number } | { ok: false; cause: unknown }> {
  try {
    const { data, error } = await api.GET('/providers', {
      params: {
        query: {
          ...(opts.q ? { q: opts.q } : {}),
          ...(opts.category ? { category: opts.category } : {}),
          ...(opts.commune ? { commune: opts.commune } : {}),
          ...(opts.availableToday ? { availableToday: true } : {}),
          sort: opts.sort ?? 'relevance',
          page,
          pageSize: RECHERCHE_PAGE_SIZE,
        },
      },
    });
    if (!error && Array.isArray(data?.items) && typeof data?.total === 'number') {
      return { ok: true, items: data.items as Provider[], total: data.total };
    }
    return { ok: false, cause: error ?? 'no items or no total' };
  } catch (e) {
    return { ok: false, cause: e };
  }
}

/// A landing route param triple ({slug}/{city}/{area}) — nested URLs
/// (multi-pays MP3).
export type LandingParams = { slug: string; city: string; area: string };

/// The salon's (city, area) slugs in the locality tree — from the MP1
/// `areaId` when present, else a slug match on the legacy commune name.
function areaParamsOf(
  p: Provider,
  tree: LocalityTree,
): { city: string; area: string } | null {
  const areaSlug = p.areaId ?? (p.commune ? slugify(p.commune) : null);
  if (!areaSlug) return null;
  for (const { city, area } of allAreas(tree)) {
    if (area.slug === areaSlug) return { city: city.slug, area: area.slug };
  }
  return null;
}

/// Category×area landing params that actually have providers — for
/// generateStaticParams + the sitemap. Derived from the live catalogue.
export async function getLandingParams(
  tree: LocalityTree,
): Promise<LandingParams[]> {
  const items = await readItems('GET /providers (landing params)', () =>
    api.GET('/providers', { params: { query: { pageSize: 50 } } }),
  );
  const seen = new Map<string, LandingParams>();
  for (const p of items) {
    const catSlug = categorySlugForApiKey(p.category);
    const geo = areaParamsOf(p, tree);
    if (!catSlug || !geo) continue;
    const key = `${catSlug}/${geo.city}/${geo.area}`;
    seen.set(key, { slug: catSlug, ...geo });
  }
  return [...seen.values()];
}

/// Providers in a commune (all categories) — backs service landings, filtered
/// client-side by service name.
export async function listProvidersByCommune(
  commune: string,
): Promise<Provider[]> {
  return readItems('GET /providers (commune)', () =>
    api.GET('/providers', { params: { query: { commune, sort: 'rating' } } }),
  );
}

/// Service×area landing params with ≥1 matching provider (catalogue-derived).
export async function getServiceLandingParams(
  tree: LocalityTree,
): Promise<LandingParams[]> {
  const items = await readItems('GET /providers (service params)', () =>
    api.GET('/providers', { params: { query: { pageSize: 50 } } }),
  );
  const seen = new Map<string, LandingParams>();
  for (const p of items) {
    const geo = areaParamsOf(p, tree);
    if (!geo) continue;
    for (const svc of p.services ?? []) {
      for (const slug of serviceSlugsForName(svc.name)) {
        seen.set(`${slug}/${geo.city}/${geo.area}`, { slug, ...geo });
      }
    }
  }
  return [...seen.values()];
}
