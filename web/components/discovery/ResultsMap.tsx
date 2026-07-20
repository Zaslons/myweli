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
  DEFAULT_ZOOM,
  FALLBACK_CENTER,
  type MappableProvider,
  boundsFor,
} from '../../lib/discovery/map';
import { formatFcfa } from '../../lib/format';
import { MAP_STYLE, SalonPin } from '../map/salon-pin';

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
  center = FALLBACK_CENTER,
}: {
  items: MappableProvider[];
  hoveredId: string | null;
  selectedId: string | null;
  onSelect: (id: string | null) => void;
  /// Empty-result center — the searched city's centroid from the locality
  /// tree (multi-pays MP3); results themselves auto-fit via bounds.
  center?: [number, number];
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
          longitude: center[0],
          latitude: center[1],
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
        <div className="pointer-events-none absolute inset-0 z-sticky flex items-center justify-center">
          <p className="rounded-lg bg-secondary px-m py-s text-bodyMedium text-textSecondary shadow">
            Aucun salon à afficher sur la carte
          </p>
        </div>
      ) : null}
    </div>
  );
}

function MiniCard({ provider: p }: { provider: MappableProvider }) {
  const active = (p.services ?? []).filter((s) => s.active !== false);
  const min = active.length ? Math.min(...active.map((s) => s.price)) : null;
  return (
    <div className="min-w-44">
      <p className="font-medium text-textPrimary">{p.name}</p>
      <p className="mt-xs text-bodySmall text-textSecondary">
        {p.reviewCount > 0 ? `★ ${p.rating.toFixed(1)} · ` : ''}
        {p.commune ?? ''}
      </p>
      {min != null ? (
        <p className="mt-xs text-bodySmall text-textTertiary">
          à partir de {formatFcfa(min, p.currency ?? undefined)}
        </p>
      ) : null}
      <p className="mt-s flex gap-m text-bodyMedium">
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
    <div className="absolute right-sm top-sm z-sticky flex flex-col items-end gap-xs">
      <button
        type="button"
        onClick={locate}
        className="inline-flex min-h-12 items-center rounded-lg border border-borderStrong bg-secondary px-m text-bodyMedium text-textPrimary shadow hover:bg-surfaceVariant"
      >
        Autour de moi
      </button>
      <p
        role="status"
        className={
          note
            ? 'rounded-lg bg-secondary px-s py-xs text-bodySmall text-textSecondary shadow'
            : 'sr-only'
        }
      >
        {note ?? ''}
      </p>
    </div>
  );
}
