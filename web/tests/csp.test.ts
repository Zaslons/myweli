import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
// @ts-expect-error — next.config.mjs is plain ESM with no declaration file. Its
// RUNTIME value is precisely what this test exists to check.
import { cspDirectives, cspString } from '../next.config.mjs';

type Directives = Record<string, string[]>;

/// **The policy, and — more importantly — whether it still covers the code.**
///
/// Restating the allowlist here would only assert that I typed it twice. The
/// load-bearing test is the last one: it walks the source for third-party
/// origins and fails when one is not covered by any directive. Adding a script,
/// a tile host or an upload target without touching the CSP then breaks the
/// build instead of breaking production silently — which is the difference
/// between fixing an instance and fixing the blindness.
describe('the Content-Security-Policy', () => {
  const d = cspDirectives({ dev: false }) as Directives;

  it('bounds exfiltration — the directive that still matters here', () => {
    // script-src carries 'unsafe-inline' (see next.config.mjs for why it cannot
    // be a nonce), so this policy does not stop XSS EXECUTION. connect-src is
    // what stops an injected script shipping data to an attacker's host, and it
    // is the defect class this project has twice caught only by detection.
    expect(d['connect-src']).toContain("'self'");
    expect(d['connect-src']).not.toContain('*');
    expect(d['default-src']).toEqual(["'self'"]);
  });

  it('cannot be framed, cannot be rebased, cannot post elsewhere', () => {
    expect(d['frame-ancestors']).toEqual(["'none'"]);
    expect(d['base-uri']).toEqual(["'self'"]);
    expect(d['form-action']).toEqual(["'self'"]);
    expect(d['object-src']).toEqual(["'none'"]);
  });

  it('allows maplibre its blob worker — without it no map constructs', () => {
    // maplibre-gl.js:34 builds the worker from a Blob URL. worker-src falls
    // back to script-src when omitted, so it must be declared explicitly.
    expect(d['worker-src']).toContain('blob:');
    expect(d['img-src']).toContain('blob:');
  });

  it("'unsafe-eval' is dev-only", () => {
    expect(cspDirectives({ dev: false })['script-src']).not.toContain("'unsafe-eval'");
    expect(cspDirectives({ dev: true })['script-src']).toContain("'unsafe-eval'");
  });

  it('reports violations somewhere when a DSN exists', () => {
    // A report-only policy nobody reads is the "guard that cannot fire" pattern
    // wearing a different suit.
    const s = cspString({ dev: false, reportUri: 'https://x/api/1/security/?sentry_key=k' });
    expect(s).toContain('report-uri https://x/api/1/security/?sentry_key=k');
    expect(cspString({ dev: false, reportUri: null })).not.toContain('report-uri');
  });

  /// **Origins the source walk below CANNOT see, and that is why they are here.**
  ///
  /// The walk finds `https://…` literals. These two never appear as literals:
  /// R2 upload URLs are PRESIGNED BY THE API at runtime, and Sentry's ingest
  /// host comes from an env DSN. So the cleverer test below is structurally
  /// blind to the single most damaging omission in the whole policy — dropping
  /// `*.r2.cloudflarestorage.com` breaks every upload, and because a
  /// CSP-blocked fetch is indistinguishable from a CORS rejection,
  /// `upload-telemetry.ts` would report it as `upload_likely_cors`.
  ///
  /// Found by mutation: removing that source left the walk green. A guard whose
  /// blind spot is the worst case is the pattern this repo keeps rediscovering.
  const RUNTIME_ONLY: [directive: string, source: string, why: string][] = [
    [
      'connect-src',
      'https://*.r2.cloudflarestorage.com',
      'upload URLs are presigned by the API — never a literal in this repo',
    ],
    [
      'connect-src',
      'https://*.ingest.de.sentry.io',
      'the ingest host comes from NEXT_PUBLIC_SENTRY_DSN, not from source',
    ],
  ];

  it('COVERS THE ORIGINS NO SOURCE WALK CAN FIND', () => {
    for (const [directive, source, why] of RUNTIME_ONLY) {
      expect(
        d[directive],
        `${source} is missing from ${directive} — ${why}`,
      ).toContain(source);
    }
  });

  /// Hosts that appear in the source but are NOT subresources, so no directive
  /// governs them. Each carries its reason; an unexplained entry here is how an
  /// allowlist rots.
  const NOT_SUBRESOURCES: [pattern: RegExp, why: string][] = [
    [/^schema\.org$/, 'a JSON-LD @context string, never fetched'],
    [/^wa\.me$/, 'a WhatsApp link href — a top-level navigation'],
    [/^calendar\.google\.com$/, 'an "add to calendar" link href'],
    [
      /^www\.instagram\.com$/,
      'the brand social profile — a footer link href and a `sameAs` string, '
        + 'both top-level navigations rather than fetches',
    ],
    [/^pay\.wave\.com$/, 'a Mobile Money link href'],
    [/^www\.google\.com$/, 'a Maps search link href'],
    [/^apps\.apple\.com$/, 'a store link href'],
    [/^play\.google\.com$/, 'a store link href'],
    [/^myweli\.com$/, 'our own origin'],
    [/^api\.myweli\.com$/, 'server-side only — lib/api/client.ts is `server-only`'],
    [/^purecatamphetamine\.github\.io$/, 'removed; named only in a comment recording that'],
    [/^token\.actions\.githubusercontent\.com$/, 'CI identity, not a browser fetch'],
    [/\.vercel\.app$/, 'preview deploys, same-origin at runtime'],
    [/^(localhost|127\.0\.0\.1|cdn\.stub|example\.test|x)$/, 'test fixtures'],
  ];

  function covered(host: string): boolean {
    const sources = Object.values(d).flat();
    return sources.some((src) => {
      if (!src.startsWith('https://')) return false;
      const pat = src.slice('https://'.length);
      if (pat.startsWith('*.')) return host.endsWith(pat.slice(1));
      return host === pat;
    });
  }

  it('EVERY THIRD-PARTY ORIGIN IN THE SOURCE IS COVERED BY SOME DIRECTIVE', () => {
    const roots = ['components', 'lib', 'app'];
    const hosts = new Map<string, string>();
    const walk = (dir: string) => {
      for (const name of readdirSync(dir)) {
        const p = join(dir, name);
        if (statSync(p).isDirectory()) {
          walk(p);
          continue;
        }
        if (!/\.(ts|tsx)$/.test(p)) continue;
        const src = readFileSync(p, 'utf8');
        for (const m of src.matchAll(/https:\/\/([a-z0-9.-]+)/gi)) {
          if (!hosts.has(m[1])) hosts.set(m[1], p);
        }
      }
    };
    roots.forEach((r) => walk(r));
    expect(hosts.size, 'found no hosts at all — the walk is broken').toBeGreaterThan(5);

    const uncovered = [...hosts.entries()].filter(
      ([h]) => !NOT_SUBRESOURCES.some(([re]) => re.test(h)) && !covered(h),
    );
    expect(
      uncovered.map(([h, f]) => `${h} (${f})`),
      'a third-party origin appears in the source and no CSP directive allows '
        + 'it. Either add it to the right directive, or add it to '
        + 'NOT_SUBRESOURCES with the reason it is not a subresource',
    ).toEqual([]);
  });
});
