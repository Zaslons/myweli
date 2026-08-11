import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/// The API base resolver fails closed in production
/// (docs/design/infra-staging.md §1.3).
///
/// **What this is really guarding.** The old expression ended
/// `?? 'http://localhost:8080'`, which looks harmless because a wrong API URL
/// fails loudly with connection errors. But `lib/api/localities.ts` and
/// `lib/api/providers.ts` catch and degrade to EMPTY results, and the ISR pages
/// call them during `next build`. So a production deploy missing the variable
/// does not error — it publishes a marketplace with no salons in it, looking
/// merely new rather than broken. That is the failure these tests pin.
///
/// `resolve` reads `process.env` at call time, so each test re-imports the
/// module with a fresh environment rather than relying on import order.
async function freshImport() {
  vi.resetModules();
  return import('../lib/api-base');
}

const originalEnv = { ...process.env };

beforeEach(() => {
  delete process.env.API_BASE_URL;
  delete process.env.NEXT_PUBLIC_API_BASE_URL;
});

afterEach(() => {
  process.env = { ...originalEnv };
});

describe('production refuses to guess', () => {
  beforeEach(() => vi.stubEnv('NODE_ENV', 'production'));
  afterEach(() => vi.unstubAllEnvs());

  it('throws when neither variable is set', async () => {
    const { resolveApiBase } = await freshImport();
    expect(() => resolveApiBase()).toThrow(/must be set in production/);
  });

  it('throws for the public resolver too', async () => {
    const { resolvePublicApiBase } = await freshImport();
    expect(() => resolvePublicApiBase()).toThrow(/NEXT_PUBLIC_API_BASE_URL/);
  });

  it('treats an empty or whitespace value as unset', async () => {
    // A platform that injects an unset reference hands you '' or padding. The
    // old `??` chain accepted both as real values and happily built against
    // them.
    for (const raw of ['', '   ', '\t']) {
      process.env.API_BASE_URL = raw;
      const { resolveApiBase } = await freshImport();
      expect(() => resolveApiBase()).toThrow(/must be set in production/);
    }
  });

  it('the message says what actually goes wrong, not just "unset"', async () => {
    // An operator reading this at 2am needs to know the consequence — an empty
    // site — because "API_BASE_URL must be set" alone reads like a nit.
    const { resolveApiBase } = await freshImport();
    expect(() => resolveApiBase()).toThrow(/no salons/);
  });

  it('resolves when configured, and trims', async () => {
    process.env.API_BASE_URL = '  https://api.myweli.com  ';
    const { resolveApiBase } = await freshImport();
    expect(resolveApiBase()).toBe('https://api.myweli.com');
  });

  it('prefers the server-only variable over the public one', async () => {
    // API_BASE_URL is the internal URL and never reaches the browser bundle.
    process.env.API_BASE_URL = 'http://api-internal:8080';
    process.env.NEXT_PUBLIC_API_BASE_URL = 'https://api.myweli.com';
    const { resolveApiBase, resolvePublicApiBase } = await freshImport();
    expect(resolveApiBase()).toBe('http://api-internal:8080');
    // ...but the client bundle must only ever see the public one.
    expect(resolvePublicApiBase()).toBe('https://api.myweli.com');
  });
});

describe('development keeps the zero-setup default', () => {
  it('falls back to localhost when nothing is configured', async () => {
    // The guard must not make local work harder — that is why it is scoped to
    // production rather than applied unconditionally.
    const { resolveApiBase, resolvePublicApiBase } = await freshImport();
    expect(resolveApiBase()).toBe('http://localhost:8080');
    expect(resolvePublicApiBase()).toBe('http://localhost:8080');
  });
});
