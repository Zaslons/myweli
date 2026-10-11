/// The CARTO basemap every web map draws on (docs/design/map-basemap-key.md).
///
/// The CARTO Positron GL style — the VECTOR twin of the apps' `light_all`
/// raster basemap (OpenMapTiles schema — the open-source version of the stack
/// Planity buys from Woosmap).
export const CARTO_STYLE_BASE =
  'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json';

/// The style URL, keyed when there is a key.
///
/// Since 2026-09-25 CARTO serves no RASTER tile without a key (the apps'
/// basemap); the GL style the web uses still loads keyless today, and CARTO
/// says the requirement may extend to it. So: keyed when
/// `NEXT_PUBLIC_CARTO_BASEMAPS_KEY` is set (the WEB key, restricted to
/// myweli.com — the apps carry their own), keyless otherwise, exactly as
/// before. Never a fallback that hides a missing key: if CARTO starts refusing
/// keyless styles, a keyless deployment shows it.
///
/// Pure (the key is a parameter) so both branches are testable; the env read
/// lives at the call site (`components/map/salon-pin.tsx`), where Next inlines
/// it at build time.
export function cartoStyleUrl(key: string | undefined | null): string {
  const k = (key ?? '').trim();
  return k ? `${CARTO_STYLE_BASE}?key=${encodeURIComponent(k)}` : CARTO_STYLE_BASE;
}
