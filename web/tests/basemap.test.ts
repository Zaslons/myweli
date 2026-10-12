import { execFile } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs';
import { createServer, type OutgoingHttpHeaders } from 'node:http';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
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

describe('MAP_STYLE + MAP_TRANSFORM_REQUEST — what every web map is handed', () => {
  /// Both read NEXT_PUBLIC_CARTO_BASEMAPS_KEY at the call site
  /// (`components/map/salon-pin.tsx`). A misspelt name, or `undefined` in place
  /// of the read, still compiles and still renders — keyless — so each export is
  /// held to the variable, not just the pure function behind it.
  const VECTOR_TILE =
    'https://tiles-a.basemaps.cartocdn.com/vectortiles/carto.streets/v1/12/2002/1987.mvt';

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.resetModules();
  });

  it('carries NEXT_PUBLIC_CARTO_BASEMAPS_KEY when it is set', async () => {
    vi.stubEnv('NEXT_PUBLIC_CARTO_BASEMAPS_KEY', 'web-key');
    vi.resetModules();
    const { MAP_STYLE, MAP_TRANSFORM_REQUEST } = await import('../components/map/salon-pin');
    expect(MAP_STYLE).toBe(`${CARTO_STYLE_BASE}?key=web-key`);
    expect(new URL(MAP_TRANSFORM_REQUEST(VECTOR_TILE).url).searchParams.get('key')).toBe(
      'web-key',
    );
  });

  it('is the keyless style, and passes requests through, when it is not', async () => {
    vi.stubEnv('NEXT_PUBLIC_CARTO_BASEMAPS_KEY', '');
    vi.resetModules();
    const { MAP_STYLE, MAP_TRANSFORM_REQUEST } = await import('../components/map/salon-pin');
    expect(MAP_STYLE).toBe(CARTO_STYLE_BASE);
    expect(MAP_TRANSFORM_REQUEST(VECTOR_TILE).url).toBe(VECTOR_TILE);
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

  it('each map renderer is handed MAP_STYLE and MAP_TRANSFORM_REQUEST', () => {
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

describe('production-checks asks CARTO, daily, whether vector still loads keyless', () => {
  /// The web runs keyless BY DECISION (spec §7: the 1 M/month free tier is
  /// shared by every key, every salon page renders a map, and keyless vector
  /// costs nothing today). That decision expires the day CARTO extends its key
  /// requirement to vector — which nothing in this repository can see. So
  /// `.github/workflows/production-checks.yml` asks CARTO every morning, and
  /// this holds the job in place AND runs its very script, both ways, against a
  /// local server: a text pin would pass a script whose test was inverted.
  const wf = readFileSync(join('..', '.github', 'workflows', 'production-checks.yml'), 'utf8');

  /// One job's block — raw, not comment-stripped, because its script is run.
  /// (`registration-claim.test.ts` → `yamlJob` for why it is anchored per job.)
  const job = (name: string) =>
    wf.match(new RegExp(`^  ${name}:$[\\s\\S]*?(?=^  \\S[^\\n]*:$|$(?![\\s\\S]))`, 'm'))?.[0] ?? '';

  /// The `run: |` body, de-indented — exactly what the runner hands to bash.
  const runScript = (block: string): string => {
    const lines = block.split('\n');
    const at = lines.findIndex((l) => /^\s+run: \|\s*$/.test(l));
    if (at < 0) return '';
    const indent = /^ */.exec(lines[at + 1] ?? '')![0].length;
    const body: string[] = [];
    for (const l of lines.slice(at + 1)) {
      if (l.trim() !== '' && /^ */.exec(l)![0].length < indent) break;
      body.push(l.slice(indent));
    }
    return body.join('\n');
  };

  const basemap = job('basemap');
  const script = runScript(basemap);
  const KEYLESS_TILE =
    'https://tiles-a.basemaps.cartocdn.com/vectortiles/carto.streets/v1/12/2002/1987.mvt';

  it('the job exists, asks for ONE keyless vector tile, and cannot be silenced', () => {
    expect(basemap, 'no `basemap` job in production-checks.yml').not.toBe('');
    expect(basemap.match(/^\s+TILE: (\S+)\s*$/m)?.[1], 'the probed URL changed').toBe(KEYLESS_TILE);
    expect(basemap, 'continue-on-error makes the probe unable to fail').not.toContain(
      'continue-on-error',
    );
    expect(script, 'the job runs no script').toContain('curl');
    expect(wf, 'the workflow lost its schedule').toMatch(/^\s+- cron: /m);
  });

  it('a red probe reaches the tracking issue', () => {
    // `report` runs on `failure()`, which only sees the jobs in its `needs`.
    const needs = job('report').match(/needs:\s*\[([^\]]*)\]/)?.[1] ?? '';
    expect(
      needs.split(',').map((n) => n.trim()),
      'basemap is not in report.needs, so a red probe opens nothing',
    ).toContain('basemap');
  });

  describe('the script itself, against a local CARTO', () => {
    const tile = (status: number, headers: OutgoingHttpHeaders, body: string) => ({
      status,
      headers,
      body,
    });
    const PBF = 'application/x-protobuf';
    const ROUTES: Record<string, ReturnType<typeof tile>> = {
      '/free.mvt': tile(200, { 'content-type': PBF, etag: 'W/"11ac4-ok"' }, 'x'.repeat(64)),
      // CARTO's raster refusal is a 200 — a watermark with a `wm-` etag.
      '/watermark.mvt': tile(200, { 'content-type': PBF, etag: '"wm-da89c20e77c1-light"' }, 'x'),
      '/weak-watermark.mvt': tile(200, { 'content-type': PBF, etag: 'W/"wm-1"' }, 'x'),
      '/a-png.mvt': tile(200, { 'content-type': 'image/png', etag: '"p"' }, 'x'),
      '/empty.mvt': tile(200, { 'content-type': PBF, etag: '"e"' }, ''),
      '/refused.mvt': tile(403, { 'content-type': 'text/plain' }, 'API KEY REQUIRED'),
    };
    const server = createServer((req, res) => {
      const r = ROUTES[req.url ?? ''];
      res.writeHead(r?.status ?? 404, r?.headers ?? {});
      res.end(r?.body ?? '');
    });
    let base = '';
    const dirs: string[] = [];

    beforeAll(async () => {
      await new Promise<void>((ok) => server.listen(0, '127.0.0.1', ok));
      base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    });
    afterAll(async () => {
      await new Promise<void>((ok) => server.close(() => ok()));
      for (const d of dirs) rmSync(d, { recursive: true, force: true });
    });

    /// Asynchronous on purpose: a synchronous spawn would block the very event
    /// loop the local server answers on.
    const probe = (url: string) =>
      new Promise<{ code: number; out: string }>((resolve) => {
        const cwd = mkdtempSync(join(tmpdir(), 'carto-probe-'));
        dirs.push(cwd);
        execFile('bash', ['-c', script], { cwd, env: { ...process.env, TILE: url } }, (err, o, e) =>
          resolve({ code: err ? Number(err.code ?? -1) : 0, out: `${o}${e}` }),
        );
      });

    it('passes on a 200 protobuf tile', async () => {
      const r = await probe(`${base}/free.mvt`);
      expect(r.out).toContain('still free');
      expect(r.code, r.out).toBe(0);
    }, 20_000);

    it('fails on everything else, naming the variable and the spec step', async () => {
      for (const path of [
        '/watermark.mvt',
        '/weak-watermark.mvt',
        '/a-png.mvt',
        '/empty.mvt',
        '/refused.mvt',
      ]) {
        const r = await probe(`${base}${path}`);
        expect(r.code, `${path} passed: ${r.out}`).toBe(1);
        expect(r.out, path).toContain('::error::');
        expect(r.out, path).toContain('NEXT_PUBLIC_CARTO_BASEMAPS_KEY');
        expect(r.out, path).toContain('map-basemap-key.md §9');
      }
    }, 20_000);

    it('fails when CARTO cannot be reached — nothing measured is not green', async () => {
      // Port 1: refused at once, and curl does not retry a refused connection.
      const r = await probe('http://127.0.0.1:1/x.mvt');
      expect(r.code, r.out).toBe(1);
      expect(r.out).toContain('could not reach CARTO');
    }, 20_000);
  });
});
