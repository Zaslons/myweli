'use client';

import { markerColor } from '../../lib/discovery/map';

/// Shared MyWeli map identity (docs/design/web-discovery-map.md §3) — used by
/// the /recherche results map AND the salon page's Localisation map so every
/// map on the site looks the same.

/// The CARTO Positron gl style — the VECTOR twin of the app MapScreen's
/// `light_all` raster basemap (keyless/free; OpenMapTiles schema — the
/// open-source version of the stack Planity buys from Woosmap).
export const MAP_STYLE =
  'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json';

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

/// maplibre stamps `role="button"` + « Map marker » on its wrapper div at
/// addTo() — but only when no role exists. Our child IS the real control
/// (named button, focusable), so a wrapper-button around it is axe's
/// `nested-interactive`. A ref callback claims the wrapper as presentation
/// FIRST: React commits children before the library Marker's addTo effect.
export function presentationalMarkerRef(el: HTMLElement | null) {
  el?.parentElement?.setAttribute('role', 'presentation');
}

/// The app's `_SalonMarker`: 44px white circle, 2px category ring, category
/// icon (20px) in the category color (§7 tokens via `currentColor`). The
/// click is handled by the library Marker (a native listener on the marker
/// element — clicks on portaled children reach it by bubbling).
export function SalonPin({
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
      ref={presentationalMarkerRef}
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
