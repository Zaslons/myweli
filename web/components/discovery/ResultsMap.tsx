'use client';

import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import Link from 'next/link';
import { useEffect, useMemo, useRef, useState } from 'react';
import { MapContainer, Marker, Popup, TileLayer, useMap } from 'react-leaflet';
import {
  ABIDJAN_CENTER,
  DEFAULT_ZOOM,
  type MappableProvider,
  boundsFor,
  markerColor,
} from '../../lib/discovery/map';
import { formatFcfa } from '../../lib/format';

/// The /recherche map pane (docs/design/web-discovery-map.md §2) — the app's
/// MapScreen design, 1:1: CARTO light basemap (the app's tile layer), the
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
  onSelect: (id: string) => void;
}) {
  const bounds = useMemo(() => boundsFor(items), [items]);
  const [userPos, setUserPos] = useState<[number, number] | null>(null);
  const markerRefs = useRef<Record<string, L.Marker | null>>({});

  // Hover/selection activation WITHOUT remounting (a remount would close the
  // marker's own popup): toggle a class on the marker element; the scale
  // transition lives on the inner pin (globals.css).
  useEffect(() => {
    for (const p of items) {
      const el = markerRefs.current[p.id]?.getElement();
      el?.classList.toggle(
        'is-active',
        p.id === hoveredId || p.id === selectedId,
      );
    }
  }, [items, hoveredId, selectedId]);

  return (
    <div className="relative h-full w-full">
      <MapContainer
        center={ABIDJAN_CENTER}
        zoom={DEFAULT_ZOOM}
        scrollWheelZoom
        className="h-full w-full"
      >
        {/* The app's clean light basemap (no key); {r} = retina, per Leaflet. */}
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
          url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
          subdomains={['a', 'b', 'c', 'd']}
        />
        <KeepSizedAndFitted bounds={bounds} />
        {items.map((p) => (
          <Marker
            key={p.id}
            ref={(m) => {
              markerRefs.current[p.id] = m;
            }}
            position={[p.latitude, p.longitude]}
            icon={salonIcon(markerColor(p.category), p.category)}
            eventHandlers={{ click: () => onSelect(p.id) }}
          >
            <Popup>
              <MiniCard provider={p} />
            </Popup>
          </Marker>
        ))}
        {userPos ? <Marker position={userPos} icon={userIcon()} /> : null}
        <LocateButton onLocated={setUserPos} />
      </MapContainer>
      {items.length === 0 ? (
        <div className="pointer-events-none absolute inset-0 z-[500] flex items-center justify-center">
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
/// icon (20px) in the category color. Color rides `currentColor` so one CSS
/// rule themes the ring (globals.css).
function salonIcon(color: string, category: string | undefined): L.DivIcon {
  const path = ICON_PATHS[category ?? ''] ?? ICON_PATHS.default;
  return L.divIcon({
    className: 'myweli-marker',
    iconSize: [44, 44],
    iconAnchor: [22, 22],
    popupAnchor: [0, -24],
    html: `<span class="myweli-pin" style="color:${color}"><svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="${path}"/></svg></span>`,
  });
}

/// The app's user marker: 22px info-blue dot, 3px white ring.
function userIcon(): L.DivIcon {
  return L.divIcon({
    className: 'myweli-user',
    iconSize: [22, 22],
    iconAnchor: [11, 11],
    html: '<span class="myweli-user-dot"></span>',
  });
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

const FIT_OPTS = { padding: [40, 40] as [number, number], maxZoom: 15 };

/// Fit to the result bounds — and keep Leaflet honest about its container
/// size. The mobile « Carte » toggle mounts the map inside display:none
/// (size 0); on the zero→visible transition Leaflet must invalidateSize and
/// re-fit or tiles never load. Plain resizes only invalidate (never fight
/// the user's pan/zoom).
function KeepSizedAndFitted({
  bounds,
}: {
  bounds: [[number, number], [number, number]] | null;
}) {
  const map = useMap();
  const boundsRef = useRef(bounds);
  boundsRef.current = bounds;

  useEffect(() => {
    if (!bounds) return;
    map.fitBounds(bounds, FIT_OPTS);
  }, [map, bounds]);

  useEffect(() => {
    const el = map.getContainer();
    let wasZero = el.clientWidth === 0 || el.clientHeight === 0;
    const ro = new ResizeObserver(() => {
      const zero = el.clientWidth === 0 || el.clientHeight === 0;
      if (!zero) {
        map.invalidateSize();
        if (wasZero && boundsRef.current) {
          map.fitBounds(boundsRef.current, FIT_OPTS);
        }
      }
      wasZero = zero;
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [map]);
  return null;
}

/// « Autour de moi » — the app's geolocation centering + user dot, with its
/// denial copy.
function LocateButton({
  onLocated,
}: {
  onLocated: (pos: [number, number]) => void;
}) {
  const map = useMap();
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
      (pos) => {
        const at: [number, number] = [
          pos.coords.latitude,
          pos.coords.longitude,
        ];
        onLocated(at);
        map.flyTo(at, 14);
      },
      () => setNote('Autorisez la localisation pour vous centrer'),
    );
  }

  return (
    <div className="leaflet-top leaflet-right">
      <div className="leaflet-control m-s flex flex-col items-end gap-xs">
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
    </div>
  );
}
