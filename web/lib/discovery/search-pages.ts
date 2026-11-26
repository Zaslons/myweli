import type { Provider } from '../api/providers';
import { readJson, send } from '../api/network';

/// `/recherche`'s pages (docs/design/consumer-search.md §3.3, A4w, decision 233): 24 salons
/// a page, « Afficher plus de salons » for the next, and the pages read kept in the address
/// (`pages=N`) so « Retour » from a salon and a reload show the same rows. Shared by the
/// server page, which reads pages 1 to N, and the browser, which reads one more.

/// Salons per page on `/recherche`. The API clamps at 50 (`backend/routes/providers`).
export const RECHERCHE_PAGE_SIZE = 24;

/// The most pages the address keeps, and so the most reads a reload makes: 240 salons.
export const RECHERCHE_MAX_PAGES = 10;

/// `pages` from the address: a whole number from 1 to [RECHERCHE_MAX_PAGES]; anything else is
/// 1 — a typed `pages=999` does not make 999 reads.
export function pagesFromParam(raw: string | undefined): number {
  if (!raw || !/^[0-9]+$/.test(raw)) return 1;
  const n = Number(raw);
  return n >= 1 && n <= RECHERCHE_MAX_PAGES ? n : 1;
}

/// More salons than the [pages] read (§2.6: `pages × 24 < total`).
export function hasMorePages(pages: number, total: number): boolean {
  return pages * RECHERCHE_PAGE_SIZE < total;
}

/// [more] after [rows], without a salon already shown. The pages are offsets: a salon
/// published, or moved up the ranking (a new review under « Mieux notés »), between two reads
/// pushes the rest down by one, and the next page starts with the last one shown. The other
/// way — a salon unpublished — pulls the rest up and one is skipped, as in the app (§2.6);
/// paging by offset cannot see that.
export function appendNew(rows: Provider[], more: Provider[]): Provider[] {
  const seen = new Set(rows.map((p) => p.id));
  const out = [...rows];
  for (const p of more) {
    if (seen.has(p.id)) continue;
    seen.add(p.id);
    out.push(p);
  }
  return out;
}

/// The search a page belongs to: what `/recherche` shows, in the address's words.
export type RechercheSearch = {
  q: string;
  commune: string;
  category: string;
  sort: string;
  dispo: boolean;
};

/// One more page, read by the browser through the same-origin route
/// (`app/api/recherche/route.ts`): the browser never calls the API host.
///
/// Not ok — nothing answered, a refusal, or a 200 without its items or its `total` — is
/// « Impossible d’afficher la suite. »: a page with no total is not a count of 0.
export async function fetchSearchPage(
  search: RechercheSearch,
  page: number,
): Promise<{ ok: true; items: Provider[]; total: number } | { ok: false }> {
  const qs = new URLSearchParams();
  if (search.q) qs.set('q', search.q);
  if (search.commune) qs.set('commune', search.commune);
  if (search.category) qs.set('category', search.category);
  // Always sent, as the server's own reads send it: the next page in the same order.
  qs.set('sort', search.sort || 'relevance');
  if (search.dispo) qs.set('availableToday', 'true');
  qs.set('page', String(page));
  const res = await send(`/api/recherche?${qs.toString()}`);
  if (!res.ok) return { ok: false };
  const body = await readJson<{ items?: unknown; total?: unknown }>(res);
  if (!body || !Array.isArray(body.items) || typeof body.total !== 'number') {
    return { ok: false };
  }
  return { ok: true, items: body.items as Provider[], total: body.total };
}

/// The address with [pages] in it, the rest kept — written with `replaceState` after each
/// page, so it moves no history entry. It stops at [RECHERCHE_MAX_PAGES]; one page is no
/// `pages` at all, the address the search had.
export function addressWithPages(current: string, pages: number): string {
  const url = new URL(current, 'https://myweli.com');
  if (pages > 1) url.searchParams.set('pages', String(Math.min(pages, RECHERCHE_MAX_PAGES)));
  else url.searchParams.delete('pages');
  const qs = url.searchParams.toString();
  return qs ? `${url.pathname}?${qs}` : url.pathname;
}
