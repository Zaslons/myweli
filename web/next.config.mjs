import { withSentryConfig } from '@sentry/nextjs';

/// The 17 SEO taxonomy roots (5 categories + 13 services, `massage` overlapping), duplicated from `lib/taxonomy.ts` because a
/// `.mjs` config cannot import TypeScript. `tests/legacy-redirects.test.ts`
/// fails if the two lists ever disagree — the same "two halves of a contract,
/// pinned by a test" shape `legal.test.tsx` uses for the mobile slug contract.
export const TAXONOMY_ROOTS = [
  'coiffure',
  'barbier',
  'onglerie',
  'spa',
  'massage',
  'tresses',
  'tissage',
  'defrisage',
  'coupe-homme',
  'barbe',
  'coupe-femme',
  'locks',
  'coloration',
  'manucure',
  'pedicure',
  'ongles',
  'soin-visage',
];

/// **The legacy flat landings (`/coiffure-cocody`) 308 from HERE, not from a
/// page.** They used to redirect inside `app/[slug]/page.tsx`. That stopped
/// working the moment that route closed its params: a PRERENDERED redirect
/// answers 308 with **no `Location` header at all** — the redirect lives in the
/// RSC payload, exactly like the 404 shell this whole change is about, and
/// `redirects.spec.ts` caught it. A config redirect is a real HTTP redirect,
/// resolved before routing, so it is immune to that.
///
/// The tree is fetched at build. If it comes back empty the build FAILS rather
/// than silently shipping a site where every legacy URL 404s.
async function legacyFlatRedirects() {
  const base =
    process.env.API_BASE_URL ?? process.env.NEXT_PUBLIC_API_BASE_URL ?? '';
  if (!base) {
    throw new Error(
      'No API base URL: cannot build the legacy flat redirects. '
        + 'Set NEXT_PUBLIC_API_BASE_URL.',
    );
  }
  const res = await fetch(`${base}/localities`);
  if (!res.ok) throw new Error(`GET /localities -> ${res.status}`);
  const tree = await res.json();
  const pairs = (tree.countries ?? []).flatMap((c) =>
    (c.cities ?? []).flatMap((city) =>
      (city.areas ?? []).map((area) => [city.slug, area.slug]),
    ),
  );
  if (pairs.length === 0) {
    throw new Error(
      'The locality tree yielded no areas. Refusing to build: every legacy '
        + 'flat URL would 404.',
    );
  }
  return TAXONOMY_ROOTS.flatMap((root) =>
    pairs.map(([city, area]) => ({
      source: `/${root}-${area}`,
      destination: `/${root}/${city}/${area}`,
      permanent: true,
    })),
  );
}


/// The Content-Security-Policy, exported so a test can assert its content
/// without a build. `tests/csp.test.ts` imports this exactly as
/// `tests/legacy-redirects.test.ts` imports TAXONOMY_ROOTS.
///
/// **Every entry below is a measured dependency, not a guess.** Three of them
/// would break production silently and are invisible to the entire local test
/// suite:
///
///   *.cartocdn.com   map tiles come from tiles-a..d.basemaps.cartocdn.com, and
///                    a bare-host source does NOT match a subdomain. Omit it and
///                    the map renders blank. Seven e2e files stub the map by
///                    substring, so they pass either way.
///   *.r2.cloudflarestorage.com
///                    uploads PUT straight at R2 from the browser, bypassing the
///                    BFF. Omit it and every upload fails — AND a CSP-blocked
///                    fetch is indistinguishable from a CORS rejection, so
///                    upload-telemetry.ts would self-report it as
///                    `upload_likely_cors` and send us chasing Cloudflare.
///   worker-src blob: maplibre builds its worker from a Blob URL
///                    (maplibre-gl.js:34). Omit it and no map constructs at all.
///
/// **`script-src 'unsafe-inline'` is forced, and the reason is worth keeping.**
/// The strongest policy is nonce-based with 'strict-dynamic'. We cannot have it:
/// Next derives a nonce from an INCOMING request header, which requires
/// middleware, and a nonce forces DYNAMIC rendering. Dynamic rendering is
/// exactly what makes `notFound()` serve the 44-character `__next_error__`
/// shell. A nonce-based CSP would reintroduce the blank-page 404 that took a
/// whole phase to fix. So this policy does not pretend to stop XSS execution —
/// what it does buy is `frame-ancestors 'none'`, `object-src 'none'`, a locked
/// `base-uri`/`form-action`, and above all a `connect-src` allowlist that bounds
/// EXFILTRATION, which is the defect class this project has now caught twice by
/// detection alone (Google's script, then GitHub Pages flags).
///
/// `style-src 'unsafe-inline'` is likewise unavoidable: next/image emits
/// `style="color:transparent"`, 22 React style props exist, and GSI injects its
/// own stylesheet. Nonces do not apply to style ATTRIBUTES.
export function cspDirectives({ dev = false, reportUri = null } = {}) {
  const d = {
    'default-src': ["'self'"],
    // 'unsafe-eval' for `next dev` only — HMR and eval-based source maps. The
    // e2e suite runs a production build, so it never needs it.
    'script-src': [
      "'self'",
      "'unsafe-inline'",
      ...(dev ? ["'unsafe-eval'"] : []),
      'https://accounts.google.com',
      'https://appleid.cdn-apple.com',
    ],
    // accounts.google.com serves the branded button's stylesheet; omitting it
    // gives an UNSTYLED Google button rather than a hard failure, which is the
    // kind of break nobody reports.
    'style-src': ["'self'", "'unsafe-inline'", 'https://accounts.google.com'],
    'img-src': ["'self'", 'data:', 'blob:', 'https://cdn.myweli.com'],
    'font-src': ["'self'"],
    'connect-src': [
      "'self'",
      'https://*.ingest.de.sentry.io',
      'https://accounts.google.com',
      'https://oauth2.googleapis.com',
      'https://*.cartocdn.com',
      'https://*.r2.cloudflarestorage.com',
    ],
    // GSI renders a cross-origin iframe. Apple opens a popup rather than a
    // frame, but appleid.apple.com is listed as insurance: the evidence is a
    // static read of one locale's bundle, and Apple has shipped iframe-based
    // variants before.
    'frame-src': ['https://accounts.google.com', 'https://appleid.apple.com'],
    'worker-src': ['blob:'],
    'frame-ancestors': ["'none'"],
    'base-uri': ["'self'"],
    'form-action': ["'self'"],
    'object-src': ["'none'"],
  };
  if (reportUri) d['report-uri'] = [reportUri];
  return d;
}

export function cspString(opts) {
  return Object.entries(cspDirectives(opts))
    .map(([k, v]) => `${k} ${v.join(' ')}`)
    .join('; ');
}

/// Sentry's security-header endpoint, derived from the DSN we already have, so
/// Report-Only violations reach a person instead of a void. A report-only
/// policy nobody reads is the "guard that cannot fire" pattern in another suit.
///
/// DSN shape: https://<publicKey>@<host>/<projectId>
function sentryReportUri() {
  const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;
  if (!dsn) return null;
  try {
    const u = new URL(dsn);
    const projectId = u.pathname.replace(/^\//, '');
    if (!u.username || !projectId) return null;
    return `https://${u.host}/api/${projectId}/security/?sentry_key=${u.username}`;
  } catch {
    return null;
  }
}

/// **Report-Only first, deliberately.** An allowlist is a claim about traffic
/// that has not happened yet, and production currently holds ZERO salons — the
/// booking and salon-page journeys cannot be exercised at all. Enforcing a
/// policy derived only from what is reachable today would be a guess. The flip
/// to enforcing is a follow-up, gated on real violation reports rather than on
/// someone remembering.
///
/// HSTS is NOT set here: Vercel already sends
/// `strict-transport-security: max-age=63072000`, and re-declaring it risks
/// weakening it. Measured on the deployed site rather than assumed.
async function securityHeaders() {
  const dev = process.env.NODE_ENV !== 'production';
  return [
    {
      // One entry, not many: `redirects()` above already emits 17 x communes
      // routes into the same Vercel routing budget.
      source: '/:path*',
      headers: [
        { key: 'X-Frame-Options', value: 'DENY' },
        { key: 'X-Content-Type-Options', value: 'nosniff' },
        { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
        {
          key: 'Content-Security-Policy-Report-Only',
          value: cspString({ dev, reportUri: sentryReportUri() }),
        },
      ],
    },
  ];
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  env: {
    // Vercel sets VERCEL_GIT_COMMIT_SHA on every build; exposing it as
    // NEXT_PUBLIC_RELEASE is what makes Sentry's release health work without
    // anyone having to set a variable per deploy — which nobody would do
    // reliably, so "release" would end up undefined and every error would group
    // under "no release". Empty string locally, which the SDK treats as unset.
    NEXT_PUBLIC_RELEASE:
      process.env.NEXT_PUBLIC_RELEASE ?? process.env.VERCEL_GIT_COMMIT_SHA ?? '',
  },
  async redirects() {
    return legacyFlatRedirects();
  },
  async headers() {
    return securityHeaders();
  },
  experimental: {
    // Required on Next 14 for `instrumentation.ts` to run at all (stable in 15).
    // Without it the Sentry server/edge init is a file nobody imports.
    instrumentationHook: true,
  },
  images: {
    // Hosts allowed for next/image. Salon photos come from the R2 public bucket
    // (R2_PUBLIC_BASE_URL = https://cdn.myweli.com at deploy); the R2 default
    // endpoint and the hermetic e2e stub host are allowed too.
    remotePatterns: [
      { protocol: 'https', hostname: 'cdn.myweli.com' },
      { protocol: 'https', hostname: '**.r2.cloudflarestorage.com' },
      { protocol: 'https', hostname: 'cdn.stub' }, // e2e stub images
    ],
  },
};

/// `withSentryConfig` is what loads `sentry.client.config.ts` and wires the
/// build. Without it the SDK config files are inert — the build stays green and
/// nothing is ever reported, which is the failure this whole slice exists to
/// prevent.
///
/// Source-map upload is skipped when `SENTRY_AUTH_TOKEN` is unset, so a
/// developer or CI without Sentry credentials still builds. Stack traces are
/// then minified until the token is configured — noted rather than hidden.
export default withSentryConfig(nextConfig, {
  silent: true,
  // Do not fail a build because telemetry could not be uploaded.
  errorHandler: () => {},
});
