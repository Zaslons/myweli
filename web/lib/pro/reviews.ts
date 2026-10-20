/// Pure summary math for the pro « Avis » page
/// (docs/design/web-pro-reviews.md §3) — the app ReviewsScreen's summary
/// card: average + the 5→1 rating distribution. Unit-tested.

export type ReviewStats = {
  average: number;
  count: number;
  /// Index 0 = 5 stars … index 4 = 1 star (display order).
  distribution: { rating: number; count: number; pct: number }[];
};

export function reviewStats(items: { rating: number }[]): ReviewStats {
  const count = items.length;
  const average =
    count === 0 ? 0 : items.reduce((sum, r) => sum + r.rating, 0) / count;
  const distribution = [5, 4, 3, 2, 1].map((rating) => {
    const n = items.filter((r) => Math.round(r.rating) === rating).length;
    return { rating, count: n, pct: count === 0 ? 0 : (n / count) * 100 };
  });
  return { average, count, distribution };
}

/// The server's card for the WHOLE salon (`/me/provider/reviews` →
/// `summary`, docs/design/salon-reviews-summary.md).
export type ReviewSummary = {
  average: number;
  count: number;
  distribution: Record<'1' | '2' | '3' | '4' | '5', number>;
};

/// The card from the server's summary — the page only lists. [reviewStats]
/// stays for a server that does not send one yet.
export function statsFromSummary(s: ReviewSummary): ReviewStats {
  const distribution = ([5, 4, 3, 2, 1] as const).map((rating) => {
    const n = s.distribution[String(rating) as '1'] ?? 0;
    return { rating, count: n, pct: s.count === 0 ? 0 : (n / s.count) * 100 };
  });
  return { average: s.average, count: s.count, distribution };
}
