import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/// docs/WEB.md §7. We report errors only, so the build removes Sentry's tracing
/// code: about 45 KB of script on every page, and most of the home page's room in
/// its LCP budget. The trap is the other direction: with `removeTracing` on, setting
/// a sample rate does nothing and says nothing. So the two must never disagree.
const WEB = join(__dirname, '..');
const read = (f: string) => readFileSync(join(WEB, f), 'utf8');
const code = (s: string) =>
  s
    .split('\n')
    .filter((line) => !/^\s*(\/\/|\*|\/\*)/.test(line))
    .join('\n');

describe('Sentry’s tracing code is gone, and tracing is off', () => {
  it('the build removes it', () => {
    expect(code(read('next.config.mjs'))).toMatch(/removeTracing:\s*true/);
  });

  for (const file of ['sentry.client.config.ts', 'sentry.server.config.ts', 'sentry.edge.config.ts']) {
    it(`${file} samples nothing, so nothing is silently lost`, () => {
      const rates = [...code(read(file)).matchAll(/tracesSampleRate:\s*([^,\s]+)/g)].map((m) => m[1]);
      expect(rates).toEqual(['0']);
    });
  }
});
