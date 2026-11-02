import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/// docs/design/web-swiss-direction.md §5, WEB-SYSTEM §3 — the file behind the
/// font, and what the source may say about it. Whether it actually renders is
/// asked of a browser in e2e/served-html.spec.ts.
const WEB = join(__dirname, '..');
const FILE = join(WEB, 'styles/fonts/hanken-grotesk-latin-400-600.woff2');

describe('the brand font', () => {
  it('is a real woff2, within its budget', () => {
    const bytes = readFileSync(FILE);
    expect(bytes.subarray(0, 4).toString('latin1')).toBe('wOF2');
    // The full file (34.7 KB) cost 300 ms of LCP and went over budget. Growing this
    // is a decision, with a new measurement of five runs, not a side effect of an
    // update (docs/WEB.md §7).
    expect(bytes.length).toBeLessThanOrEqual(20 * 1024);
  });

  it('travels with its licence, as the OFL requires', () => {
    const licence = readFileSync(join(WEB, 'styles/fonts/OFL.txt'), 'utf8');
    expect(licence).toMatch(/Hanken Grotesk/);
    expect(licence).toMatch(/SIL Open Font License/i);
  });

  it('swaps instead of hiding text, adjusts its fallback, and stays preloaded', () => {
    const source = readFileSync(join(WEB, 'styles/font.ts'), 'utf8');
    expect(source).toMatch(/display: 'swap'/);
    expect(source).toMatch(/variable: '--font-brand'/);
    expect(source).toMatch(/adjustFontFallback: 'Arial'/);
    // `preload: false` looks like a saving and makes first paint 300 ms worse.
    expect(source).not.toMatch(/preload:\s*false/);
  });

  it('never comes from a third party', () => {
    const walk = (dir: string): string[] =>
      readdirSync(dir).flatMap((name) => {
        const p = join(dir, name);
        return statSync(p).isDirectory() ? walk(p) : /\.(tsx?|css|mjs)$/.test(name) ? [p] : [];
      });
    const foreign = ['app', 'components', 'lib', 'styles']
      .flatMap((d) => walk(join(WEB, d)))
      // Code, not comments: GoogleSignInButton's documents the host Google's own
      // sign-in script loads, and that is a sentence about a script, not a font of ours.
      .filter((f) =>
        readFileSync(f, 'utf8')
          .split('\n')
          .filter((line) => !/^\s*(\/\/|\*|\/\*)/.test(line))
          .some((line) => /next\/font\/google|fonts\.(googleapis|gstatic)\.com/.test(line)),
      );
    expect(foreign).toEqual([]);
  });
});
