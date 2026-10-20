import { describe, expect, it } from 'vitest';
import { reviewStats, statsFromSummary } from '../lib/pro/reviews';

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

/// docs/design/salon-reviews-summary.md — the card's numbers are the
/// server's, for the whole salon; the loaded page only lists.
describe('statsFromSummary', () => {
  it('the server’s average, count and split, in display order', () => {
    const s = statsFromSummary({
      average: 4,
      count: 60,
      distribution: { '5': 30, '4': 20, '3': 0, '2': 0, '1': 10 },
    });
    expect(s.average).toBe(4);
    expect(s.count).toBe(60);
    expect(s.distribution.map((d) => d.rating)).toEqual([5, 4, 3, 2, 1]);
    expect(s.distribution[0]).toEqual({ rating: 5, count: 30, pct: 50 });
    expect(s.distribution[4].pct).toBeCloseTo(16.67, 1);
  });

  it('no review: zeros, no division by zero', () => {
    const s = statsFromSummary({
      average: 0,
      count: 0,
      distribution: { '5': 0, '4': 0, '3': 0, '2': 0, '1': 0 },
    });
    expect(s.distribution.every((d) => d.pct === 0)).toBe(true);
  });
});
