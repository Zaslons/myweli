'use client';

import 'maplibre-gl/dist/maplibre-gl.css';
import { Map, Marker, NavigationControl } from '@vis.gl/react-maplibre';
import { useState } from 'react';
import { ABIDJAN_CENTER } from '../../lib/discovery/map';
import { MAP_STYLE } from '../map/salon-pin';

/// The salon pin picker (docs/design/pro-salon-lifecycle.md L1): tap or drag
/// the marker onto the salon, or « Utiliser ma position ». Same MapLibre +
/// Positron identity as every map on the site.
export function LocationPicker({
  latitude,
  longitude,
  onChange,
}: {
  latitude: number | null;
  longitude: number | null;
  onChange: (lat: number, lng: number) => void;
}) {
  const placed = latitude != null && longitude != null;
  const [note, setNote] = useState<string | null>(null);

  function locate() {
    if (!navigator.geolocation) {
      setNote('Localisation indisponible');
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => onChange(pos.coords.latitude, pos.coords.longitude),
      () => setNote('Autorisez la localisation pour vous placer'),
    );
  }

  return (
    <div>
      <div className="h-64 w-full overflow-hidden rounded-lg border border-border md:h-80">
        <Map
          initialViewState={{
            longitude: longitude ?? ABIDJAN_CENTER[0],
            latitude: latitude ?? ABIDJAN_CENTER[1],
            zoom: placed ? 15 : 11,
          }}
          mapStyle={MAP_STYLE}
          cooperativeGestures
          style={{ width: '100%', height: '100%' }}
          onClick={(e) => onChange(e.lngLat.lat, e.lngLat.lng)}
        >
          <NavigationControl position="top-left" showCompass={false} />
          {placed ? (
            <Marker
              longitude={longitude}
              latitude={latitude}
              anchor="center"
              draggable
              onDragEnd={(e) => onChange(e.lngLat.lat, e.lngLat.lng)}
            >
              <span className="myweli-pin" style={{ color: '#000000' }}>
                <svg
                  width="20"
                  height="20"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" />
                </svg>
              </span>
            </Marker>
          ) : null}
        </Map>
      </div>
      <div className="mt-s flex flex-wrap items-center gap-m">
        <button
          type="button"
          onClick={locate}
          className="rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary hover:bg-surfaceVariant"
        >
          Utiliser ma position
        </button>
        <p className="text-xs text-textTertiary">
          {placed
            ? 'Glissez le repère ou touchez la carte pour ajuster.'
            : 'Touchez la carte pour placer votre salon.'}
        </p>
        {note ? <p className="text-xs text-error">{note}</p> : null}
      </div>
    </div>
  );
}
