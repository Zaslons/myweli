'use client';

import dynamic from 'next/dynamic';
import { Loading } from '../Loading';
import { useEffect, useMemo, useRef, useState } from 'react';
import { defaultCity, findCity, type LocalityTree } from '../../lib/api/localities';
import type { Provider } from '../../lib/api/providers';
import { resolveArea } from '../../lib/discovery';
import { categoryList } from '../../lib/landing';
import { centerOf, withCoords } from '../../lib/discovery/map';
import {
  addFavorite,
  getFavorites,
  removeFavorite,
} from '../../lib/api/account';
import { HomeSearch } from '../home/HomeSearch';
import { ProviderCard } from '../provider/ProviderCard';

// Leaflet is browser-only → client-side dynamic import; the chunk loads only
// on /recherche (public-page CWV budgets untouched).
const ResultsMap = dynamic(
  () => import('./ResultsMap').then((m) => m.ResultsMap),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full w-full items-center justify-center bg-surfaceVariant">
        <Loading label="Chargement de la carte…" />
      </div>
    ),
  },
);

/// The /recherche split view (docs/design/web-discovery-map.md §2), Planity-
/// style: search + chips + results in the LEFT column, the map FULL-BLEED on
/// the right — no frame, flush to the viewport edges, pinning to the full
/// screen height as the list scrolls. Mobile web keeps the list + a floating
/// « Carte »/« Liste » toggle to an edge-to-edge map. Two-way sync: card
/// hover highlights the marker; a marker click selects + scrolls its card.
const SORT_OPTIONS: { value: string; label: string }[] = [
  { value: 'relevance', label: 'Pertinence' },
  { value: 'rating', label: 'Mieux notés' },
  { value: 'price', label: 'Prix croissant' },
];

export function RechercheClient({
  title,
  results,
  q,
  commune,
  category,
  sort,
  dispo,
  tree,
}: {
  title: string;
  results: Provider[];
  q: string;
  commune: string;
  category: string;
  sort: string;
  dispo: boolean;
  /// The locality tree (multi-pays MP3) — search suggestions/routing + the
  /// map's empty-result center.
  tree: LocalityTree;
}) {
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  // Parity 2.15: hearts on the result cards — ONE session probe (anonymous
  // 401 → null keeps the hearts as login CTAs).
  const [favIds, setFavIds] = useState<Set<string> | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [mobileView, setMobileView] = useState<'list' | 'map'>('list');
  const cardRefs = useRef<Record<string, HTMLDivElement | null>>({});

  const mappable = withCoords(results);
  // Map center for empty results: the searched commune's city, else the
  // home market's first city (results themselves auto-fit via bounds).
  const mapCenter = useMemo(() => {
    const area = commune ? resolveArea(commune, tree) : null;
    const city = area ? findCity(tree, area.citySlug) : defaultCity(tree);
    return centerOf(city);
  }, [commune, tree]);

  useEffect(() => {
    let active = true;
    getFavorites().then((r) => {
      if (active && r.status === 200) {
        setFavIds(new Set(r.favorites.map((f) => f.id)));
      }
    });
    return () => {
      active = false;
    };
  }, []);

  async function toggleFavorite(id: string) {
    if (favIds === null) {
      const back = `${window.location.pathname}${window.location.search}`;
      window.location.assign(`/connexion?returnTo=${encodeURIComponent(back)}`);
      return;
    }
    const isFav = favIds.has(id);
    const r = isFav ? await removeFavorite(id) : await addFavorite(id);
    if (!r.ok) return;
    setFavIds((cur) => {
      const next = new Set(cur);
      if (isFav) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  // A marker click brings the matching card into view (desktop sync).
  useEffect(() => {
    if (!selectedId) return;
    cardRefs.current[selectedId]?.scrollIntoView({
      behavior: 'smooth',
      block: 'nearest',
    });
  }, [selectedId]);

  // Every control re-navigates with the OTHER filters preserved (SSR refetch).
  const hrefWith = (patch: {
    category?: string | null;
    sort?: string;
    dispo?: boolean;
  }) => {
    const qs = new URLSearchParams();
    if (q) qs.set('q', q);
    if (commune) qs.set('commune', commune);
    const cat = patch.category === undefined ? category : patch.category;
    if (cat) qs.set('category', cat);
    const srt = patch.sort ?? sort;
    if (srt && srt !== 'relevance') qs.set('sort', srt);
    const dsp = patch.dispo === undefined ? dispo : patch.dispo;
    if (dsp) qs.set('dispo', '1');
    const str = qs.toString();
    return `/recherche${str ? `?${str}` : ''}`;
  };

  const chipHref = (apiKey: string | null) => hrefWith({ category: apiKey });

  return (
    <div
      // ds-ignore: the list/map split ratio — a layout template, not a reusable token.
      // eslint-disable-next-line tailwindcss/no-arbitrary-value
      className="lg:grid lg:grid-cols-[minmax(0,55%)_minmax(0,1fr)]"
    >
      {/* LEFT — search header + chips + the results list (scrolls with the page). */}
      <div
        className={`px-m py-l lg:px-l ${mobileView === 'map' ? 'hidden lg:block' : ''}`}
      >
        <h1 className="text-headlineSmall font-semibold text-textPrimary">{title}</h1>
        <div className="mt-m">
          <HomeSearch tree={tree} defaultService={q} defaultCommune={commune} />
        </div>

        {/* Category chips — « filter by type » without retyping the search. */}
        <div className="mt-m flex flex-wrap gap-s" aria-label="Catégories">
          <a
            href={chipHref(null)}
            className={`inline-flex min-h-12 items-center rounded-pill border px-m text-bodyMedium ${
              !category
                ? 'border-primary bg-primary text-secondary'
                : 'border-border bg-surface text-textPrimary'
            }`}
          >
            Tous
          </a>
          {categoryList.map((c) => (
            <a
              key={c.apiKey}
              href={chipHref(c.apiKey)}
              className={`inline-flex min-h-12 items-center rounded-pill border px-m text-bodyMedium ${
                category === c.apiKey
                  ? 'border-primary bg-primary text-secondary'
                  : 'border-border bg-surface text-textPrimary'
              }`}
            >
              {c.label}
            </a>
          ))}
        </div>

        {/* Trier + « Disponible aujourd'hui » (parity 2.1/2.2 — FR-DISC-007). */}
        <div className="mt-m flex flex-wrap items-center gap-s">
          <label className="flex items-center gap-s text-bodyMedium text-textSecondary">
            Trier
            <select
              value={sort}
              onChange={(e) => {
                window.location.assign(hrefWith({ sort: e.target.value }));
              }}
              className="min-h-12 rounded-lg border border-borderStrong bg-surface px-s py-xs text-bodyMedium text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
            >
              {SORT_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          </label>
          <a
            href={hrefWith({ dispo: !dispo })}
            aria-current={dispo ? 'true' : undefined}
            className={`inline-flex min-h-12 items-center rounded-pill border px-m text-bodyMedium ${
              dispo
                ? 'border-primary bg-primary text-secondary'
                : 'border-border bg-surface text-textPrimary'
            }`}
          >
            Disponible aujourd’hui
          </a>
        </div>

        {results.length > 0 ? (
          <h2 className="mt-m text-titleLarge font-semibold text-textPrimary">
            {results.length} salon{results.length > 1 ? 's' : ''}
          </h2>
        ) : null}
        <div className="mt-m space-y-m">
          {results.length === 0 ? (
            <div className="rounded-xl border border-border bg-secondary p-l text-center text-textSecondary">
              Aucun salon trouvé. Essayez une autre recherche ou une autre
              commune.
            </div>
          ) : (
            results.map((p) => (
              <div
                key={p.id}
                ref={(el) => {
                  cardRefs.current[p.id] = el;
                }}
                role="presentation"
                onMouseEnter={() => setHoveredId(p.id)}
                onMouseLeave={() => setHoveredId(null)}
                // §5: hover-only affordances must also work on focus — the card
                // contains focusable children, so capture their focus/blur.
                onFocus={() => setHoveredId(p.id)}
                onBlur={() => setHoveredId(null)}
                className={
                  selectedId === p.id
                    ? 'rounded-xl ring-2 ring-primary'
                    : undefined
                }
              >
                <ProviderCard
                  provider={p}
                  favorite={favIds?.has(p.id) ?? false}
                  onToggleFavorite={() => toggleFavorite(p.id)}
                />
              </div>
            ))
          )}
        </div>
      </div>

      {/* RIGHT — the map, part of the screen: no frame, flush to the right
          edge, full viewport height once the (non-sticky) header scrolls by. */}
      <div className={mobileView === 'map' ? 'block' : 'hidden lg:block'}>
        {/* In the mobile « Carte » view the left column — and with it the
            page's only h1 — is display:none. Keep a heading in the a11y
            tree; lg:hidden keeps it single at desktop, where the real h1
            is visible again. */}
        <h1 className="sr-only lg:hidden">{title}</h1>
        <div
          // ds-ignore: viewport arithmetic (full height minus the header) — no token can express
          // a calc().
          // eslint-disable-next-line tailwindcss/no-arbitrary-value
          className="h-[calc(100dvh-6.5rem)] lg:sticky lg:top-0 lg:h-screen"
        >
          <ResultsMap
            items={mappable}
            hoveredId={hoveredId}
            selectedId={selectedId}
            onSelect={setSelectedId}
            center={mapCenter}
          />
        </div>
      </div>

      {/* Mobile floating toggle — the app's map tab, web-shaped. */}
      <button
        type="button"
        onClick={() => setMobileView((v) => (v === 'list' ? 'map' : 'list'))}
        className="fixed bottom-l left-1/2 z-sticky inline-flex min-h-12 -translate-x-1/2 items-center rounded-pill bg-primary px-l text-labelLarge font-medium text-secondary shadow-lg lg:hidden"
      >
        {mobileView === 'list' ? 'Carte' : 'Liste'}
      </button>
    </div>
  );
}
