'use client';

import 'maplibre-gl/dist/maplibre-gl.css';
import Link from 'next/link';
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Map,
  type MapRef,
  Marker,
  NavigationControl,
  Popup,
} from '@vis.gl/react-maplibre';
import {
  ABIDJAN_CENTER,
  DEFAULT_ZOOM,
  type MappableProvider,
  boundsFor,
  markerColor,
} from '../../lib/discovery/map';
import { formatFcfa } from '../../lib/format';

/// The CARTO Positron gl style — the VECTOR twin of the app MapScreen's
/// `light_all` raster basemap (same design language, still keyless/free;
/// OpenMapTiles schema — the stack Planity buys from Woosmap, open-source).
const MAP_STYLE = 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json';

const FIT_OPTS = { padding: 40, maxZoom: 15 };

/// The /recherche map pane (docs/design/web-discovery-map.md §2) — the app's
/// MapScreen design on MapLibre GL: Positron vector basemap, the
/// white-circle + category-icon salon markers, the info-blue user dot,
/// « Autour de moi », auto-fit to the results. Full-bleed — framing is the
/// page's job.
export function ResultsMap({
  items,
  hoveredId,
  selectedId,
  onSelect,
}: {
  items: MappableProvider[];
  hoveredId: string | null;
  selectedId: string | null;
  onSelect: (id: string | null) => void;
}) {
  const mapRef = useRef<MapRef>(null);
  const bounds = useMemo(() => boundsFor(items), [items]);
  const [loaded, setLoaded] = useState(false);
  const [userPos, setUserPos] = useState<[number, number] | null>(null);

  // Fit the viewport to the result bounds once the style is up (and again
  // whenever the result set changes); none mappable → stay on Abidjan.
  useEffect(() => {
    if (!loaded || !bounds) return;
    mapRef.current?.fitBounds(bounds, FIT_OPTS);
  }, [loaded, bounds]);

  const selected = items.find((p) => p.id === selectedId) ?? null;

  return (
    <div className="relative h-full w-full">
      <Map
        ref={mapRef}
        initialViewState={{
          longitude: ABIDJAN_CENTER[0],
          latitude: ABIDJAN_CENTER[1],
          zoom: DEFAULT_ZOOM,
        }}
        mapStyle={MAP_STYLE}
        onLoad={() => setLoaded(true)}
        style={{ width: '100%', height: '100%' }}
      >
        <NavigationControl position="top-left" showCompass={false} />
        {items.map((p) => {
          const active = p.id === hoveredId || p.id === selectedId;
          return (
            <Marker
              key={p.id}
              longitude={p.longitude}
              latitude={p.latitude}
              anchor="center"
              style={{ zIndex: active ? 2 : 1 }}
              onClick={() => onSelect(p.id)}
            >
              <SalonPin category={p.category} active={active} name={p.name} />
            </Marker>
          );
        })}
        {userPos ? (
          <Marker longitude={userPos[0]} latitude={userPos[1]} anchor="center">
            <span className="myweli-user-dot" />
          </Marker>
        ) : null}
        {selected ? (
          <Popup
            longitude={selected.longitude}
            latitude={selected.latitude}
            anchor="bottom"
            offset={28}
            maxWidth="280px"
            // The selecting click itself bubbles to the map AFTER React has
            // mounted the popup — the default closeOnClick would close it in
            // the same gesture. Deselect = the ✕ or another marker.
            closeOnClick={false}
            onClose={() => onSelect(null)}
          >
            <MiniCard provider={selected} />
          </Popup>
        ) : null}
      </Map>
      <LocateButton
        onLocate={(pos) => {
          setUserPos(pos);
          mapRef.current?.flyTo({ center: pos, zoom: 14 });
        }}
      />
      {items.length === 0 ? (
        <div className="pointer-events-none absolute inset-0 z-10 flex items-center justify-center">
          <p className="rounded-lg bg-secondary px-m py-s text-sm text-textSecondary shadow">
            Aucun salon à afficher sur la carte
          </p>
        </div>
      ) : null}
    </div>
  );
}

// The app's category icons (Material Design, Apache 2.0): spa · content_cut
// (barber) · face (salon) · store_mall_directory (default).
const ICON_PATHS: Record<string, string> = {
  spa: 'M15.49 9.63c-.18-2.79-1.31-5.51-3.43-7.63-2.14 2.14-3.32 4.86-3.55 7.63 1.28.68 2.46 1.56 3.49 2.63 1.03-1.06 2.21-1.94 3.49-2.63zM12 15.45C9.85 12.17 6.18 10 2 10c0 5.32 3.36 9.82 8.03 11.49.63.23 1.29.4 1.97.51.68-.12 1.33-.29 1.97-.51C18.64 19.82 22 15.32 22 10c-4.18 0-7.85 2.17-10 5.45z',
  barber:
    'M9.64 7.64c.23-.5.36-1.05.36-1.64 0-2.21-1.79-4-4-4S2 3.79 2 6s1.79 4 4 4c.59 0 1.14-.13 1.64-.36L10 12l-2.36 2.36C7.14 14.13 6.59 14 6 14c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4c0-.59-.13-1.14-.36-1.64L12 14l7 7h3v-1L9.64 7.64zM6 8c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm0 12c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm6-7.5c-.28 0-.5-.22-.5-.5s.22-.5.5-.5.5.22.5.5-.22.5-.5.5zM19 3l-6 6 2 2 7-7V3h-3z',
  salon:
    'M9 11.75c-.69 0-1.25.56-1.25 1.25s.56 1.25 1.25 1.25 1.25-.56 1.25-1.25-.56-1.25-1.25-1.25zm6 0c-.69 0-1.25.56-1.25 1.25s.56 1.25 1.25 1.25 1.25-.56 1.25-1.25-.56-1.25-1.25-1.25zM12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8 0-.29.02-.58.05-.86 2.36-1.05 4.23-2.98 5.21-5.37C11.07 8.33 14.05 10 17.42 10c.78 0 1.53-.09 2.25-.26.21.71.33 1.47.33 2.26 0 4.41-3.59 8-8 8z',
  default:
    'M20 4H4v2h16V4zm1 10v-2l-1-5H4l-1 5v2h1v6h10v-6h4v6h2v-6h1zm-9 4H6v-4h6v4z',
};

/// The app's `_SalonMarker`: 44px white circle, 2px category ring, category
/// icon (20px) in the category color (§7 tokens via `currentColor`). The
/// click is handled by the library Marker (a native listener on the marker
/// element — clicks on portaled children reach it by bubbling).
function SalonPin({
  category,
  active,
  name,
}: {
  category: string | undefined;
  active: boolean;
  name: string;
}) {
  const path = ICON_PATHS[category ?? ''] ?? ICON_PATHS.default;
  return (
    <button
      type="button"
      aria-label={`Voir ${name} sur la carte`}
      className={`myweli-marker myweli-pin${active ? ' is-active' : ''}`}
      style={{ color: markerColor(category) }}
    >
      <svg
        width="20"
        height="20"
        viewBox="0 0 24 24"
        fill="currentColor"
        aria-hidden="true"
      >
        <path d={path} />
      </svg>
    </button>
  );
}

function MiniCard({ provider: p }: { provider: MappableProvider }) {
  const active = (p.services ?? []).filter((s) => s.active !== false);
  const min = active.length ? Math.min(...active.map((s) => s.price)) : null;
  return (
    <div className="min-w-44">
      <p className="font-medium text-textPrimary">{p.name}</p>
      <p className="mt-xs text-xs text-textSecondary">
        {p.reviewCount > 0 ? `★ ${p.rating.toFixed(1)} · ` : ''}
        {p.commune ?? ''}
      </p>
      {min != null ? (
        <p className="mt-xs text-xs text-textTertiary">
          à partir de {formatFcfa(min)}
        </p>
      ) : null}
      <p className="mt-s flex gap-m text-sm">
        <Link href={`/${p.slug}`} className="underline">
          Voir le salon
        </Link>
        <Link href={`/${p.slug}/reserver`} className="font-medium underline">
          Réserver
        </Link>
      </p>
    </div>
  );
}

/// « Autour de moi » — the app's geolocation centering + user dot, with its
/// denial copy. Overlaid on the map (top-right, clear of the zoom control).
function LocateButton({
  onLocate,
}: {
  onLocate: (pos: [number, number]) => void;
}) {
  const [note, setNote] = useState<string | null>(null);

  useEffect(() => {
    if (!note) return;
    const t = setTimeout(() => setNote(null), 3000);
    return () => clearTimeout(t);
  }, [note]);

  function locate() {
    if (!navigator.geolocation) {
      setNote('Localisation indisponible');
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => onLocate([pos.coords.longitude, pos.coords.latitude]),
      () => setNote('Autorisez la localisation pour vous centrer'),
    );
  }

  return (
    <div className="absolute right-3 top-3 z-10 flex flex-col items-end gap-xs">
      <button
        type="button"
        onClick={locate}
        className="rounded-lg border border-border bg-secondary px-m py-s text-sm text-textPrimary shadow hover:bg-surfaceVariant"
      >
        Autour de moi
      </button>
      {note ? (
        <p className="rounded-lg bg-secondary px-s py-xs text-xs text-textSecondary shadow">
          {note}
        </p>
      ) : null}
    </div>
  );
}
