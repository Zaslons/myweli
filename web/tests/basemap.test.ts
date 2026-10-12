import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { CARTO_STYLE_BASE, cartoStyleUrl, cartoTransformRequest } from '../lib/basemap';

/// The web's keyed CARTO style (docs/design/map-basemap-key.md).

describe('cartoStyleUrl', () => {
  it('keys the documented GL style path when there is a key', () => {
    expect(cartoStyleUrl('k-123')).toBe(
      'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json?key=k-123',
    );
  });

  it('stays keyless without one — exactly the URL the web always used', () => {
    for (const none of [undefined, null, '', '   ']) {
      expect(cartoStyleUrl(none)).toBe(CARTO_STYLE_BASE);
    }
    expect(CARTO_STYLE_BASE).toBe(
      'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
    );
  });

  it('trims and encodes the key — it can never break out of the query', () => {
    expect(cartoStyleUrl(' k-1 \n')).toBe(`${CARTO_STYLE_BASE}?key=k-1`);
    expect(cartoStyleUrl('a&b=c#d')).toBe(`${CARTO_STYLE_BASE}?key=a%26b%3Dc%23d`);
  });
});

describe('MAP_STYLE — what every web map is handed', () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.resetModules();
  });

  it('carries NEXT_PUBLIC_CARTO_BASEMAPS_KEY when it is set', async () => {
    vi.stubEnv('NEXT_PUBLIC_CARTO_BASEMAPS_KEY', 'web-key');
    vi.resetModules();
    const { MAP_STYLE } = await import('../components/map/salon-pin');
    expect(MAP_STYLE).toBe(`${CARTO_STYLE_BASE}?key=web-key`);
  });

  it('is the keyless style when it is not', async () => {
    vi.stubEnv('NEXT_PUBLIC_CARTO_BASEMAPS_KEY', '');
    vi.resetModules();
    const { MAP_STYLE } = await import('../components/map/salon-pin');
    expect(MAP_STYLE).toBe(CARTO_STYLE_BASE);
  });
});

describe('every web map goes through the one keyed style', () => {
  /// Code only — full-line `//` / `///` comments dropped, so a sentence about
  /// the host cannot satisfy or trip the guard.
  const code = (src: string) =>
    src
      .split('\n')
      .filter((l) => !l.trimStart().startsWith('//'))
      .join('\n');

  const files = new Map<string, string>();
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (/\.(ts|tsx)$/.test(p)) files.set(p.replaceAll('\\', '/'), code(readFileSync(p, 'utf8')));
    }
  };
  ['app', 'components', 'lib'].forEach(walk);

  it('the walk sees the source at all (positive control)', () => {
    expect(files.size).toBeGreaterThan(50);
    expect(files.get('lib/basemap.ts')).toContain('basemaps.cartocdn.com');
  });

  it('no other file names the CARTO host — a new map cannot go keyless', () => {
    const offenders = [...files.entries()]
      .filter(([p, src]) => p !== 'lib/basemap.ts' && src.includes('cartocdn.com'))
      .map(([p]) => p);
    expect(offenders).toEqual([]);
  });

  it('each map renderer is handed MAP_STYLE', () => {
    const maps = [...files.entries()].filter(([, src]) => /<Map\b/.test(src));
    expect(maps.map(([p]) => p).sort()).toEqual([
      'components/discovery/ResultsMap.tsx',
      'components/pro/LocationPicker.tsx',
      'components/provider/SalonLocationMap.tsx',
    ]);
    for (const [p, src] of maps) {
      expect(src, p).toContain('mapStyle={MAP_STYLE}');
      expect(src, p).toContain('transformRequest={MAP_TRANSFORM_REQUEST}');
    }
  });
});

describe('cartoTransformRequest — the requests after the style', () => {
  const keyed = cartoTransformRequest('web-key');

  it('keys tiles.json, vector tiles, sprite and glyphs on every CARTO host', () => {
    for (const url of [
      'https://tiles.basemaps.cartocdn.com/vector/carto.streets/v1/tiles.json',
      'https://tiles-a.basemaps.cartocdn.com/vectortiles/carto.streets/v1/12/2002/1987.mvt',
      'https://tiles.basemaps.cartocdn.com/gl/positron-gl-style/sprite@2x.json',
      'https://tiles.basemaps.cartocdn.com/fonts/Montserrat%20Medium/0-255.pbf',
    ]) {
      const out = new URL(keyed(url).url);
      expect(out.searchParams.get('key'), url).toBe('web-key');
      expect(`${out.origin}${out.pathname}`, url).toBe(url);
    }
  });

  it('never touches another host, and never overwrites a key', () => {
    for (const url of [
      'https://api.myweli.com/providers',
      'https://cdn.myweli.com/a.jpg',
      'https://evil.example/cartocdn.com/x.png',
      'https://cartocdn.com.evil.example/x.png',
    ]) {
      expect(keyed(url).url, url).toBe(url);
    }
    const already = `${CARTO_STYLE_BASE}?key=other`;
    expect(keyed(already).url).toBe(already);
  });

  it('is a pass-through without a key, or on a URL it cannot parse', () => {
    for (const none of [undefined, null, '', '  ']) {
      const t = cartoTransformRequest(none);
      const url = 'https://tiles-a.basemaps.cartocdn.com/vectortiles/carto.streets/v1/1/1/1.mvt';
      expect(t(url).url).toBe(url);
    }
    expect(keyed('not a url').url).toBe('not a url');
  });
});
