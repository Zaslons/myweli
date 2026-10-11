'use client';

import { Icon, type IconName } from '../Icon';
import { cartoStyleUrl } from '../../lib/basemap';
import { markerColor } from '../../lib/discovery/map';

/// Shared MyWeli map identity (docs/design/web-discovery-map.md §3) — used by
/// the /recherche results map AND the salon page's Localisation map so every
/// map on the site looks the same.

/// The CARTO Positron GL style every web map uses — keyed with the WEB key
/// when `NEXT_PUBLIC_CARTO_BASEMAPS_KEY` is set (docs/design/map-basemap-key.md).
/// The env read must stay a literal `process.env.NEXT_PUBLIC_…` access: that is
/// what Next inlines into the client bundle at build time.
export const MAP_STYLE = cartoStyleUrl(
  process.env.NEXT_PUBLIC_CARTO_BASEMAPS_KEY,
);

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
function categoryIcon(category: string | undefined): IconName {
  if (category === 'spa' || category === 'barber' || category === 'salon')
    return category;
  return 'store';
}

export function SalonPin({
  category,
  active,
  name,
}: {
  category: string | undefined;
  active: boolean;
  name: string;
}) {
  return (
    <button
      type="button"
      ref={presentationalMarkerRef}
      aria-label={`Voir ${name} sur la carte`}
      className={`myweli-marker myweli-pin${active ? ' is-active' : ''}`}
      style={{ color: markerColor(category) }}
    >
      <Icon name={categoryIcon(category)} size="iconS" />
    </button>
  );
}
