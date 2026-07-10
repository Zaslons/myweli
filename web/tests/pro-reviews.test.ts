import { describe, expect, it } from 'vitest';
import { reviewStats } from '../lib/pro/reviews';

/// « Avis » summary math (docs/design/web-pro-reviews.md §3) — the app
/// ReviewsScreen's average + 5→1 distribution.

describe('reviewStats', () => {
  it('empty → zeroed stats, distribution still 5→1', () => {
    const s = reviewStats([]);
    expect(s.average).toBe(0);
    expect(s.count).toBe(0);
    expect(s.distribution.map((d) => d.rating)).toEqual([5, 4, 3, 2, 1]);
    expect(s.distribution.every((d) => d.count === 0 && d.pct === 0)).toBe(true);
  });

  it('averages and buckets a mixed set', () => {
    const s = reviewStats([
      { rating: 5 },
      { rating: 5 },
      { rating: 4 },
      { rating: 1 },
    ]);
    expect(s.average).toBeCloseTo(3.75);
    expect(s.count).toBe(4);
    expect(s.distribution[0]).toEqual({ rating: 5, count: 2, pct: 50 });
    expect(s.distribution[1]).toEqual({ rating: 4, count: 1, pct: 25 });
    expect(s.distribution[4]).toEqual({ rating: 1, count: 1, pct: 25 });
  });

  it('rounds fractional ratings into the nearest bucket', () => {
    const s = reviewStats([{ rating: 4.6 }]);
    expect(s.distribution[0].count).toBe(1); // → the 5-star bar
  });
});
