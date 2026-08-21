import { describe, expect, it } from 'vitest';
import production from '../tool/lighthouse-production.json';
import local from '../lighthouserc.json';

/// **docs/WEB.md §7 states LCP < 2.5s and CLS < 0.1. This makes the real-domain
/// gate actually say that.**
///
/// It did not. `/connexion` carried an LCP ceiling of **2900 ms** in both
/// configs — a deliberate ratchet against the LOCAL build's 2774 ms median. But
/// the same 2900 was copied into the PRODUCTION config, where `/connexion`
/// measures **1457 ms**: a ceiling with 1443 ms of slack does not enforce
/// anything, while §7 goes on claiming the budget is enforced.
///
/// The local config keeps its looser ceiling deliberately — an un-CDN'd
/// localhost build is genuinely slower, and tightening it there would fail on
/// something production does not have. That asymmetry is now explicit rather
/// than accidental, and this test is what keeps it from drifting back.
const WEB_MD_LCP_MS = 2500;
const WEB_MD_CLS = 0.1;

type Matrix = {
  matchingUrlPattern: string;
  aggregationMethod?: string;
  assertions: Record<string, [string, Record<string, number>]>;
};

describe('the real-domain CWV gate enforces the documented budget', () => {
  const matrices = production.ci.assert.assertMatrix as unknown as Matrix[];

  it('measures the real domain, not localhost', () => {
    for (const u of production.ci.collect.url) {
      expect(u).toMatch(/^https:\/\/myweli\.com/);
    }
  });

  for (const m of matrices) {
    describe(m.matchingUrlPattern, () => {
      it(`asserts LCP at or below WEB.md §7's ${WEB_MD_LCP_MS}ms`, () => {
        const [level, opts] = m.assertions['largest-contentful-paint'];
        expect(level, 'a warn cannot fail the run').toBe('error');
        expect(opts.maxNumericValue).toBeLessThanOrEqual(WEB_MD_LCP_MS);
      });

      it(`asserts CLS at or below ${WEB_MD_CLS}`, () => {
        const [level, opts] = m.assertions['cumulative-layout-shift'];
        expect(level).toBe('error');
        expect(opts.maxNumericValue).toBeLessThanOrEqual(WEB_MD_CLS);
      });

      /// lhci's default is **optimistic** — the best of N runs. Three runs of a
      /// flaky page then report the luckiest one, which is how a gate flatters.
      /// It must be set inside each matrix block; at the top level lhci errors
      /// with "Cannot use assertMatrix with other options".
      it('takes the MEDIAN of the runs, not the best', () => {
        expect(m.aggregationMethod).toBe('median');
      });
    });
  }

  /// **The hole this file was added to close, found in this file.**
  ///
  /// Every assertion above iterates `assertMatrix` — so it checks that the
  /// blocks which EXIST are strict, and nothing at all about whether a measured
  /// URL has a block. Delete the `/connexion` matrix entry and every test here
  /// still passes while that page is measured and asserted against nothing.
  /// That is the plan's own rule 1, in the guard written to enforce rule 1.
  it('EVERY MEASURED URL IS ACTUALLY ASSERTED', () => {
    for (const url of production.ci.collect.url) {
      const covering = matrices.filter((m) =>
        new RegExp(m.matchingUrlPattern).test(url),
      );
      expect(
        covering.length,
        `${url} is collected but no assertMatrix pattern matches it — it is `
          + 'measured and then ignored',
      ).toBeGreaterThan(0);
    }
  });

  it('and no matrix block is dead — every pattern matches something', () => {
    // The inverse: a pattern that matches no collected URL is a budget nobody
    // is subject to, which reads as coverage on the page and is not.
    for (const m of matrices) {
      const hit = production.ci.collect.url.some((u) =>
        new RegExp(m.matchingUrlPattern).test(u),
      );
      expect(hit, `${m.matchingUrlPattern} matches no collected URL`).toBe(true);
    }
  });

  it('runs each URL more than once, or a median means nothing', () => {
    expect(production.ci.collect.numberOfRuns).toBeGreaterThan(1);
  });

  it('the LOCAL config may be looser, and is — deliberately', () => {
    // Stated so that someone tightening this later knows it was a choice: an
    // un-CDN'd localhost build measures ~2774ms on /connexion where production
    // measures 1457ms.
    const localMatrices = local.ci.assert.assertMatrix as unknown as Matrix[];
    const connexion = localMatrices.find((m) =>
      m.matchingUrlPattern.includes('connexion'),
    );
    expect(connexion).toBeDefined();
    expect(
      connexion!.assertions['largest-contentful-paint'][1].maxNumericValue,
    ).toBeGreaterThanOrEqual(WEB_MD_LCP_MS);
  });
});
