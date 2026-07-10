'use client';

import dynamic from 'next/dynamic';
import { useEffect, useRef, useState } from 'react';
import type { Provider } from '../../lib/api/providers';
import { categoryList } from '../../lib/landing';
import { withCoords } from '../../lib/discovery/map';
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
        <p className="text-sm text-textSecondary">Chargement de la carte…</p>
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
export function RechercheClient({
  title,
  results,
  q,
  commune,
  category,
}: {
  title: string;
  results: Provider[];
  q: string;
  commune: string;
  category: string;
}) {
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [mobileView, setMobileView] = useState<'list' | 'map'>('list');
  const cardRefs = useRef<Record<string, HTMLDivElement | null>>({});

  const mappable = withCoords(results);

  // A marker click brings the matching card into view (desktop sync).
  useEffect(() => {
    if (!selectedId) return;
    cardRefs.current[selectedId]?.scrollIntoView({
      behavior: 'smooth',
      block: 'nearest',
    });
  }, [selectedId]);

  const chipHref = (apiKey: string | null) => {
    const qs = new URLSearchParams();
    if (q) qs.set('q', q);
    if (commune) qs.set('commune', commune);
    if (apiKey) qs.set('category', apiKey);
    const s = qs.toString();
    return `/recherche${s ? `?${s}` : ''}`;
  };

  return (
    <div className="lg:grid lg:grid-cols-[minmax(0,55%)_minmax(0,1fr)]">
      {/* LEFT — search header + chips + the results list (scrolls with the page). */}
      <div
        className={`px-m py-l lg:px-l ${mobileView === 'map' ? 'hidden lg:block' : ''}`}
      >
        <h1 className="text-2xl font-semibold text-textPrimary">{title}</h1>
        <div className="mt-m">
          <HomeSearch defaultService={q} defaultCommune={commune} />
        </div>

        {/* Category chips — « filter by type » without retyping the search. */}
        <div className="mt-m flex flex-wrap gap-s" aria-label="Catégories">
          <a
            href={chipHref(null)}
            className={`rounded-full border px-m py-xs text-sm ${
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
              className={`rounded-full border px-m py-xs text-sm ${
                category === c.apiKey
                  ? 'border-primary bg-primary text-secondary'
                  : 'border-border bg-surface text-textPrimary'
              }`}
            >
              {c.label}
            </a>
          ))}
        </div>

        <p className="mt-m text-sm text-textTertiary">
          {results.length} salon{results.length > 1 ? 's' : ''}
        </p>
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
                onMouseEnter={() => setHoveredId(p.id)}
                onMouseLeave={() => setHoveredId(null)}
                className={
                  selectedId === p.id
                    ? 'rounded-xl ring-2 ring-primary'
                    : undefined
                }
              >
                <ProviderCard provider={p} />
              </div>
            ))
          )}
        </div>
      </div>

      {/* RIGHT — the map, part of the screen: no frame, flush to the right
          edge, full viewport height once the (non-sticky) header scrolls by. */}
      <div className={mobileView === 'map' ? 'block' : 'hidden lg:block'}>
        <div className="h-[calc(100dvh-6.5rem)] lg:sticky lg:top-0 lg:h-screen">
          <ResultsMap
            items={mappable}
            hoveredId={hoveredId}
            selectedId={selectedId}
            onSelect={setSelectedId}
          />
        </div>
      </div>

      {/* Mobile floating toggle — the app's map tab, web-shaped. */}
      <button
        type="button"
        onClick={() => setMobileView((v) => (v === 'list' ? 'map' : 'list'))}
        className="fixed bottom-6 left-1/2 z-[1100] -translate-x-1/2 rounded-full bg-primary px-l py-s text-sm font-medium text-secondary shadow-lg lg:hidden"
      >
        {mobileView === 'list' ? 'Carte' : 'Liste'}
      </button>
    </div>
  );
}
