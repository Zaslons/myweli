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

/// Keys every OTHER request maplibre makes to CARTO once the style is loaded —
/// tiles.json, the vector tiles, sprite, glyphs. CARTO's style.json does not
/// pass the style URL's key on to them (measured 2026-10-11 with the real web
/// key), and CARTO validates a key wherever one is present: keyed + myweli.com
/// referer → 200, keyed without a referer → 403. So a keyed style alone would
/// leave the tiles keyless the day CARTO extends the requirement to vector.
///
/// Only CARTO hosts are touched, an existing `key` is never overwritten, and
/// without a key every request passes through unchanged. Pure, like
/// `cartoStyleUrl`; the env read lives in `components/map/salon-pin.tsx`.
export function cartoTransformRequest(
  key: string | undefined | null,
): (url: string) => { url: string } {
  const k = (key ?? '').trim();
  return (url) => {
    if (!k) return { url };
    let u: URL;
    try {
      u = new URL(url);
    } catch {
      return { url };
    }
    const carto = u.hostname === 'cartocdn.com' || u.hostname.endsWith('.cartocdn.com');
    if (!carto || u.searchParams.has('key')) return { url };
    u.searchParams.set('key', k);
    return { url: u.toString() };
  };
}
