import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
// @ts-expect-error — next.config.mjs is plain ESM with no declaration file. Its
// RUNTIME value is precisely what this test exists to check.
import nextConfig, { sentryReportUri } from '../next.config.mjs';

/// docs/design/observability-error-reporting.md §8.1.1 — the CSP violation
/// reports carry their environment.
///
/// The browser posts them to the `report-uri` itself, so no SDK attaches an
/// environment. Until 2026-10-28 they arrived with none — and the web's Sentry
/// alert could not watch « production » only without going deaf to them
/// (`MYWELI-WEB-9`, a blocked `connect.facebook.net` script on myweli.com, is
/// what such a report looks like).
const DSN = 'https://pubkey@o1.ingest.de.sentry.io/4511899664318544';
const saved = {
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  env: process.env.NEXT_PUBLIC_SENTRY_ENV,
};

function restore(name: string, value: string | undefined) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}

afterEach(() => {
  restore('NEXT_PUBLIC_SENTRY_DSN', saved.dsn);
  restore('NEXT_PUBLIC_SENTRY_ENV', saved.env);
});

/// The header exactly as the built site sends it — through the exported
/// config, `withSentryConfig` included, not through a helper the header might
/// stop calling.
async function reportUriInTheHeader(): Promise<URL> {
  const cfg = typeof nextConfig === 'function' ? await nextConfig('phase-production-build', {}) : nextConfig;
  const entries: { headers: { key: string; value: string }[] }[] = await cfg.headers();
  const csp = entries
    .flatMap((e) => e.headers)
    .find((h) => h.key === 'Content-Security-Policy-Report-Only');
  expect(csp, 'no CSP header at all').toBeDefined();
  const m = csp!.value.match(/(?:^|; )report-uri (\S+)/);
  expect(m, `no report-uri in « ${csp!.value} »`).not.toBeNull();
  return new URL(m![1]);
}

describe('the CSP report-uri names its environment', () => {
  it("the built header carries the deployment's NEXT_PUBLIC_SENTRY_ENV", async () => {
    process.env.NEXT_PUBLIC_SENTRY_DSN = DSN;
    process.env.NEXT_PUBLIC_SENTRY_ENV = 'production';
    const u = await reportUriInTheHeader();
    // Still Sentry's security endpoint for this project and key.
    expect(u.host).toBe('o1.ingest.de.sentry.io');
    expect(u.pathname).toBe('/api/4511899664318544/security/');
    expect(u.searchParams.get('sentry_key')).toBe('pubkey');
    // The point: the name the alert filters on.
    expect(u.searchParams.get('sentry_environment')).toBe('production');
  });

  it('a preview names itself, so it never counts as production', async () => {
    process.env.NEXT_PUBLIC_SENTRY_DSN = DSN;
    process.env.NEXT_PUBLIC_SENTRY_ENV = 'preview';
    expect((await reportUriInTheHeader()).searchParams.get('sentry_environment')).toBe('preview');
  });

  it("unset, it falls back to the SDK's own default — never to nothing", async () => {
    process.env.NEXT_PUBLIC_SENTRY_DSN = DSN;
    delete process.env.NEXT_PUBLIC_SENTRY_ENV;
    expect((await reportUriInTheHeader()).searchParams.get('sentry_environment')).toBe(
      'development',
    );
  });

  it('the name is encoded, not pasted', () => {
    const raw = sentryReportUri({ dsn: DSN, environment: 'a b&c' }) as string;
    expect(raw).toContain('sentry_environment=a%20b%26c');
    expect(new URL(raw).searchParams.get('sentry_environment')).toBe('a b&c');
    expect(new URL(raw).searchParams.get('sentry_key')).toBe('pubkey');
  });

  it('no DSN, no report-uri (unchanged)', () => {
    expect(sentryReportUri({ dsn: undefined, environment: 'production' })).toBeNull();
    expect(sentryReportUri({ dsn: 'not a url', environment: 'production' })).toBeNull();
  });
});

/// A report and an SDK event from one deployment must land in the SAME
/// environment, or the alert watches one and not the other. The three SDK
/// configs and the header each spell the name; this goes red when one of them
/// changes the variable or the default alone (a defect), and passes when all
/// four change together (the repair).
describe('the header and the SDK name the environment the same way', () => {
  const NAME = "process.env.NEXT_PUBLIC_SENTRY_ENV ?? 'development'";
  /// Comments out, so a sentence ABOUT the expression cannot satisfy the pin.
  /// Only `/*` opening a line and `//` after whitespace count: a naive
  /// stripper reads `https://*.r2…` in the CSP as a block comment and blanks
  /// most of next.config.mjs (measured while writing this).
  const strip = (src: string) =>
    src
      .replace(/^\s*\/\*[\s\S]*?\*\//gm, (m) => m.replace(/[^\n]/g, ' '))
      .replace(/(^|\s)\/\/.*$/gm, (_m, before: string) => before);
  const read = (f: string) => strip(readFileSync(join(__dirname, '..', f), 'utf8'));

  it.each(['sentry.client.config.ts', 'sentry.server.config.ts', 'sentry.edge.config.ts'])(
    '%s',
    (f) => {
      expect(read(f)).toContain(`environment: ${NAME}`);
    },
  );

  it('next.config.mjs', () => {
    expect(read('next.config.mjs')).toContain(`environment = ${NAME}`);
  });
});
