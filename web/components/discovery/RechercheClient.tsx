'use client';

import dynamic from 'next/dynamic';
import { useEffect, useRef, useState } from 'react';
import type { Provider } from '../../lib/api/providers';
import { categoryList } from '../../lib/landing';
import { withCoords } from '../../lib/discovery/map';
import { ProviderCard } from '../provider/ProviderCard';

// Leaflet is browser-only → client-side dynamic import; the chunk loads only
// on /recherche (public-page CWV budgets untouched).
const ResultsMap = dynamic(
  () => import('./ResultsMap').then((m) => m.ResultsMap),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full w-full items-center justify-center rounded-xl border border-border bg-surface">
        <p className="text-sm text-textSecondary">Chargement de la carte…</p>
      </div>
    ),
  },
);

/// The /recherche split view (docs/design/web-discovery-map.md §2): category
/// chips over the results list (left) + the sticky map (right) on desktop;
/// a floating « Carte »/« Liste » toggle on mobile web. Two-way sync: card
/// hover highlights the marker; a marker click selects + scrolls its card.
export function RechercheClient({
  results,
  q,
  commune,
  category,
}: {
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

  const list = (
    <div>
      <p className="text-sm text-textTertiary">
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
  );

  return (
    <div>
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

      {/* Desktop: list left + sticky map right. Mobile: the toggle decides. */}
      <div className="mt-m lg:grid lg:grid-cols-[minmax(0,58%)_minmax(0,1fr)] lg:items-start lg:gap-l">
        <div className={mobileView === 'map' ? 'hidden lg:block' : ''}>
          {list}
        </div>
        <div
          className={`${
            mobileView === 'map' ? 'block' : 'hidden'
          } h-[65vh] lg:sticky lg:top-20 lg:block lg:h-[calc(100vh-6.5rem)]`}
        >
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
        className="fixed bottom-6 left-1/2 z-40 -translate-x-1/2 rounded-full bg-primary px-l py-s text-sm font-medium text-secondary shadow-lg lg:hidden"
      >
        {mobileView === 'list' ? 'Carte' : 'Liste'}
      </button>
    </div>
  );
}
