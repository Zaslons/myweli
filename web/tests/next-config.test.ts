import { describe, expect, it } from 'vitest';
// @ts-expect-error — next.config.mjs is plain ESM with no declaration file. Its
// RUNTIME value is precisely what this test exists to check.
import nextConfig from '../next.config.mjs';

/// docs/design/web-swiss-cards.md §6 and §7. Through the exported config,
/// `withSentryConfig` included, so a wrapper that dropped a key would show here.
async function images(): Promise<{
  minimumCacheTTL?: number;
  remotePatterns: { protocol: string; hostname: string }[];
}> {
  const cfg =
    typeof nextConfig === 'function' ? await nextConfig('phase-production-build', {}) : nextConfig;
  return cfg.images;
}

describe('the image optimizer’s config', () => {
  // With Next's default of 60 s most photo views would be a billed transformation.
  it('keeps a transformed photo at least 30 days', async () => {
    expect((await images()).minimumCacheTTL).toBeGreaterThanOrEqual(30 * 24 * 60 * 60);
  });

  // Anything a card can show goes through here, so a new host is a decision.
  it('allows exactly the three hosts', async () => {
    const hosts = (await images()).remotePatterns.map((p) => `${p.protocol}://${p.hostname}`);
    expect(hosts.sort()).toEqual([
      'https://**.r2.cloudflarestorage.com',
      'https://cdn.myweli.com',
      'https://cdn.stub',
    ]);
  });
});
