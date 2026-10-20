import '../../models/review.dart';
import '../../models/review_summary.dart';

/// What the « Avis » summary card shows (docs/design/salon-reviews-summary.md):
/// the server's summary — the WHOLE salon — when it sends one; otherwise the
/// loaded reviews, as the screen always did. The first page holds 50, so the
/// fallback is only right up to 50.
typedef ReviewCard = ({
  double average,
  int count,
  int Function(int star) countFor,
});

ReviewCard reviewCard(List<Review> reviews, ReviewSummary? summary) {
  if (summary != null) {
    return (
      average: summary.average,
      count: summary.count,
      countFor: (star) => summary.distribution[star] ?? 0,
    );
  }
  final count = reviews.length;
  final average = count == 0
      ? 0.0
      : reviews.map((r) => r.rating).reduce((a, b) => a + b) / count;
  return (
    average: average,
    count: count,
    countFor: (star) => reviews.where((r) => r.rating == star).length,
  );
}
