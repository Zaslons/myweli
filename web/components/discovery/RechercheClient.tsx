'use client';

import dynamic from 'next/dynamic';
import { flushSync } from 'react-dom';
import { chipLinkClasses } from '../Chip';
import { EmptyState } from '../EmptyState';
import { Loading } from '../Loading';
import { useEffect, useMemo, useRef, useState } from 'react';
import { defaultCity, findCity, type LocalityTree } from '../../lib/localities';
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
import { writeFailureMessage } from '../../lib/api/network';
import { firstPhotoIndex, ProviderCard } from '../provider/ProviderCard';
import { Toast } from '../Toast';
import { useToast } from '../../lib/useToast';
import { announceFavorite } from '../../lib/account/favorite-toast';

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
  // Parity 2.15: hearts on the result cards — ONE session probe. What it
  // ended in decides what a heart does:
  // - `loading`: nothing yet — the hearts wait (a signed-in visitor who
  //   clicked before `/api/me/favorites` answered used to be sent to the
  //   login page; it also made `account.spec.ts`'s heart assertion flaky);
  // - `known`: the hearts are the visitor's;
  // - `anonymous` (401): a heart is the way to the login page;
  // - `failed` (no usable answer): the hearts show empty and WRITE, and the
  //   write's own 401 decides — like the salon page's button. It used to be
  //   taken for anonymous: a signed-in visitor sent to log in again (B5.2,
  //   docs/design/web-client-polish.md §2.2).
  const [favIds, setFavIds] = useState<Set<string>>(() => new Set());
  const [favRead, setFavRead] = useState<'loading' | 'known' | 'anonymous' | 'failed'>(
    'loading',
  );
  // One write per card at a time (B5.2): a double click wrote twice. The ref
  // guards; the state draws the heart as busy.
  const pendingRef = useRef<Set<string>>(new Set());
  const [pending, setPending] = useState<Set<string>>(() => new Set());
  const { toast, show, dismiss } = useToast();
  // A heart the server refused: the sentence under that card only
  // (docs/design/web-consumer-optimistic-revert.md §3.2 ⑤).
  const [favErrors, setFavErrors] = useState<Record<string, string | undefined>>({});
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [mobileView, setMobileView] = useState<'list' | 'map'>('list');
  const listScrollY = useRef(0);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const cardRefs = useRef<Record<string, HTMLDivElement | null>>({});

  const mappable = withCoords(results);
  const firstPhoto = firstPhotoIndex(results);
  // Map center for empty results: the searched commune's city, else the
  // home market's first city (results themselves auto-fit via bounds).
  const mapCenter = useMemo(() => {
    const area = commune ? resolveArea(commune, tree) : null;
    const city = area ? findCity(tree, area.citySlug) : defaultCity(tree);
    return centerOf(city);
  }, [commune, tree]);

  useEffect(() => {
    let active = true;
    getFavorites()
      .then((r) => {
        if (!active) return;
        if (r.status === 200) {
          setFavIds(new Set(r.favorites.map((f) => f.id)));
          setFavRead('known');
        } else {
          setFavRead(r.status === 401 ? 'anonymous' : 'failed');
        }
      })
      .catch(() => {
        if (active) setFavRead('failed');
      });
    return () => {
      active = false;
    };
  }, []);

  function toLogin() {
    const back = `${window.location.pathname}${window.location.search}`;
    window.location.assign(`/connexion?returnTo=${encodeURIComponent(back)}`);
  }

  /// Like the app's heart, it waits for the server, then says what it did —
  /// with « Annuler » (B5.4, decision 16).
  async function toggleFavorite(id: string) {
    // Unknown is not the same as anonymous.
    if (favRead === 'loading' || pendingRef.current.has(id)) return;
    if (favRead === 'anonymous') {
      toLogin();
      return;
    }
    const adding = !favIds.has(id);
    if (await writeFavorite(id, adding)) {
      announceFavorite(show, dismiss, adding, () => void writeFavorite(id, !adding));
    }
  }

  /// One card's write. A refusal keeps the heart and says why under the
  /// card; a 401 (no session: never signed in, or ended since) is the way to
  /// the login page.
  async function writeFavorite(id: string, add: boolean): Promise<boolean> {
    if (pendingRef.current.has(id)) return false;
    pendingRef.current.add(id);
    setPending(new Set(pendingRef.current));
    setFavErrors((e) => ({ ...e, [id]: undefined }));
    const r = add ? await addFavorite(id) : await removeFavorite(id);
    pendingRef.current.delete(id);
    setPending(new Set(pendingRef.current));
    if (r.status === 401) {
      toLogin();
      return false;
    }
    if (!r.ok) {
      setFavErrors((e) => ({ ...e, [id]: writeFailureMessage(r.status) }));
      return false;
    }
    setFavIds((cur) => {
      const next = new Set(cur);
      if (add) next.add(id);
      else next.delete(id);
      return next;
    });
    return true;
  }

  // A marker click brings the matching card into view (desktop sync).
  useEffect(() => {
    if (!selectedId) return;
    cardRefs.current[selectedId]?.scrollIntoView({
      behavior: 'smooth',
      block: 'nearest',
    });
  }, [selectedId]);

  /// The map opens whole, and « Liste » goes back to where the list stood. The page under the
  /// map is short, so from far down a long list the browser would hold the page at its end:
  /// the footer alone on the screen, with the map and this button above it
  /// (docs/design/web-swiss-cards.md §2.4).
  ///
  /// « Carte » and « Liste » are two elements now, one under the list and one under the map
  /// (B11.5), so the press hands the focus to the one that appears, as the single button
  /// kept it before.
  function toggleMobileView() {
    const toMap = mobileView === 'list';
    const hadFocus = document.activeElement === toggleRef.current;
    if (toMap) listScrollY.current = window.scrollY;
    flushSync(() => setMobileView(toMap ? 'map' : 'list'));
    if (hadFocus) toggleRef.current?.focus({ preventScroll: true });
    window.scrollTo({ top: toMap ? 0 : listScrollY.current, behavior: 'instant' });
  }

  /// The mobile toggle — the app's map tab, web-shaped. At the page's gutter, over a row's
  /// photo column and off the card's text at normal text from 250 wide up, and `sticky`: it
  /// rides at the screen's foot and stops above the footer (decisions 5 and 91). Where it is
  /// placed decides what it can ride over: under the list it is the list's last child, so it
  /// floats over the rows only, never the search, the filters or « N salons » above them
  /// (B11.5). `data-floating-control` is how the toast finds it (Toast.tsx).
  /// `ml-m` only under the map: under the list the column's own `px-m` is the gutter.
  const toggle = (underMap: boolean) => (
    <button
      ref={toggleRef}
      type="button"
      onClick={toggleMobileView}
      data-floating-control=""
      className={`sticky bottom-l z-sticky flex min-h-12 w-fit items-center rounded-control bg-primary px-l text-labelLarge font-medium text-secondary shadow-lg md:landscape:hidden lg:hidden ${
        underMap ? 'ml-m' : ''
      }`}
    >
      {mobileView === 'list' ? 'Carte' : 'Liste'}
    </button>
  );

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
      // ds-ignore: the list/map split ratio — a layout template, not a reusable token. The
      // map stands beside the list from `lg`, and in a window wider than tall from `md`
      // (B11.5): there the footer is taller than the screen, so a floating « Carte » left it.
      // Every `md:landscape:` class here comes AFTER its `lg:` twin in the stylesheet, so in a
      // landscape window from `lg` it is the one that applies: keep each pair the same value.
      // eslint-disable-next-line tailwindcss/no-arbitrary-value
      className="md:landscape:grid md:landscape:grid-cols-[minmax(0,55%)_minmax(0,1fr)] lg:grid lg:grid-cols-[minmax(0,55%)_minmax(0,1fr)]"
    >
      {/* LEFT — search header + chips + the results list (scrolls with the page). No foot
          padding where « Carte » is the column's last child: it then stops 48 above the footer's
          rule, the footer's own `mt-xxl`, as it did from under the column (B11.5). */}
      <div
        className={`px-m pt-l md:landscape:pb-l lg:px-l lg:pb-l ${mobileView === 'map' ? 'hidden md:landscape:block lg:block' : ''}`}
      >
        <h1 className="text-headlineSmall font-semibold text-textPrimary">{title}</h1>
        <div className="mt-m">
          <HomeSearch tree={tree} defaultService={q} defaultCommune={commune} />
        </div>

        {/* Category chips — « filter by type » without retyping the search. */}
        <div className="mt-m flex flex-wrap gap-s" aria-label="Catégories">
          <a
            href={chipHref(null)}
            className={chipLinkClasses(!category)}
          >
            Tous
          </a>
          {categoryList.map((c) => (
            <a
              key={c.apiKey}
              href={chipHref(c.apiKey)}
              className={chipLinkClasses(category === c.apiKey)}
            >
              {c.label}
            </a>
          ))}
        </div>

        {/* Trier + « Disponible aujourd'hui » (parity 2.1/2.2 — FR-DISC-007). */}
        <div className="mt-m flex flex-wrap items-center gap-s">
          {/* `max-w-full` and `min-w-0`: with doubled text at 320 the unchanged « Trier »
              made the page 322 wide (docs/design/web-swiss-cards.md §2.3). */}
          <label className="flex max-w-full items-center gap-s text-bodyMedium text-textSecondary">
            Trier
            <select
              value={sort}
              onChange={(e) => {
                window.location.assign(hrefWith({ sort: e.target.value }));
              }}
              className="min-h-12 min-w-0 rounded-control border border-primary bg-surface px-s py-xs text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
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
            className={chipLinkClasses(dispo)}
          >
            Disponible aujourd’hui
          </a>
        </div>

        {results.length > 0 ? (
          <h2 className="mt-m text-titleLarge font-semibold text-textPrimary">
            {results.length} salon{results.length > 1 ? 's' : ''}
          </h2>
        ) : null}
        {/* The list draws the lines between rows, so a card never doubles one. The empty
            state is not inside the divide. With no result « Carte » stands under the empty
            state, in its own box, so it has nothing to ride over (B11.5). */}
        {results.length === 0 ? (
          <>
            <div className="mt-m">
              <EmptyState
                align="start"
                icon="search"
                title="Aucun salon trouvé"
                description="Essayez une autre recherche ou une autre commune."
              />
            </div>
            {mobileView === 'list' ? (
              <div className="mt-l md:landscape:hidden lg:hidden">{toggle(false)}</div>
            ) : null}
          </>
        ) : (
          // The rows and « Carte » share this box, which is what `sticky` may ride in.
          <div className="mt-xs">
            <div className="divide-y divide-divider">
              {results.map((p, i) => (
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
                  // Every row keeps its `py-m`, not `first:pt-0`: that put the first row's ring
                  // on its photo and its name. The offset keeps the ring off the photo's left
                  // edge, as the focus ring does. Square, like the row it marks.
                  className={`py-m ${
                    selectedId === p.id ? 'ring-2 ring-primary ring-offset-2 ring-offset-surface' : ''
                  }`}
                >
                  <ProviderCard
                    provider={p}
                    layout="row"
                    // docs/design/web-swiss-cards.md §7: the first photo, which can be the
                    // largest paint, fetched first. The same bytes either way.
                    imagePriority={i === firstPhoto}
                    favorite={favIds.has(p.id)}
                    onToggleFavorite={() => toggleFavorite(p.id)}
                    favoriteBusy={favRead === 'loading'}
                    favoritePending={pending.has(p.id)}
                  />
                  {favErrors[p.id] ? (
                    <p role="alert" className="mt-xs text-bodyMedium text-error">
                      {favErrors[p.id]}
                    </p>
                  ) : null}
                </div>
              ))}
            </div>
            {mobileView === 'list' ? toggle(false) : null}
          </div>
        )}
      </div>

      {/* RIGHT — the map, part of the screen: no frame, flush to the right
          edge, full viewport height once the (non-sticky) header scrolls by. */}
      <div className={mobileView === 'map' ? 'block' : 'hidden md:landscape:block lg:block'}>
        {/* In the mobile « Carte » view the left column — and with it the
            page's only h1 — is display:none. Keep a heading in the a11y
            tree; lg:hidden keeps it single at desktop, where the real h1
            is visible again. */}
        <h1 className="sr-only md:landscape:hidden lg:hidden">{title}</h1>
        <div
          // ds-ignore: viewport arithmetic (full height minus the header) — no token can express
          // a calc().
          // eslint-disable-next-line tailwindcss/no-arbitrary-value
          className="h-[calc(100dvh-6.5rem)] md:landscape:sticky md:landscape:top-0 md:landscape:h-screen lg:sticky lg:top-0 lg:h-screen"
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

      {/* In the map view « Liste » stands under the map, where the single button stood. */}
      {mobileView === 'map' ? toggle(true) : null}
      {/* The ♥'s announcement (B5.4) — centred, and above « Carte » or « Liste » wherever
          the button stands (Toast.tsx, B11.5). */}
      <Toast toast={toast} aboveFloatingControl />
    </div>
  );
}
