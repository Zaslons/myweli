'use client';

import 'leaflet/dist/leaflet.css';
import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import {
  CircleMarker,
  MapContainer,
  Popup,
  TileLayer,
  useMap,
} from 'react-leaflet';
import {
  ABIDJAN_CENTER,
  DEFAULT_ZOOM,
  type MappableProvider,
  boundsFor,
  markerColor,
} from '../../lib/discovery/map';
import { formatFcfa } from '../../lib/format';

/// The /recherche map pane (docs/design/web-discovery-map.md §2): the app's
/// MapScreen on web — OSM tiles, §7 token-colored divIcon markers, popup
/// mini-card, « Autour de moi » geolocation, auto-fit to the results.
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

  return (
    <div className="relative h-full w-full overflow-hidden rounded-xl border border-border">
      <MapContainer
        center={ABIDJAN_CENTER}
        zoom={DEFAULT_ZOOM}
        scrollWheelZoom
        className="h-full w-full"
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <FitToResults bounds={bounds} />
        {items.map((p) => {
          const active = p.id === hoveredId || p.id === selectedId;
          return (
            // CircleMarker: radius + pathOptions are MUTABLE in react-leaflet,
            // so hover/selection restyle without remounting (a remount would
            // close the marker's own popup mid-click).
            <CircleMarker
              key={p.id}
              center={[p.latitude, p.longitude]}
              radius={active ? 11 : 7}
              // className must be a CREATION option (Leaflet applies it in
              // _initPath only) — inside pathOptions it would never render.
              className="myweli-marker"
              pathOptions={{
                color: '#FFFFFF',
                weight: 2,
                fillColor: markerColor(p.category),
                fillOpacity: 1,
              }}
              eventHandlers={{ click: () => onSelect(p.id) }}
            >
              <Popup>
                <MiniCard provider={p} />
              </Popup>
            </CircleMarker>
          );
        })}
        <LocateButton />
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

/// Fit the viewport to the result bounds whenever the result set changes
/// (single result → a sane close zoom; none → stay on Abidjan).
function FitToResults({
  bounds,
}: {
  bounds: [[number, number], [number, number]] | null;
}) {
  const map = useMap();
  useEffect(() => {
    if (!bounds) return;
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 15 });
  }, [map, bounds]);
  return null;
}

/// « Autour de moi » — the app's geolocation centering, with its denial copy.
function LocateButton() {
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
      (pos) => map.flyTo([pos.coords.latitude, pos.coords.longitude], 14),
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
