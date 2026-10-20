import 'package:equatable/equatable.dart';

import 'review.dart';

/// The « Avis » card for the WHOLE salon, as the server sends it with every
/// page of `/me/provider/reviews` (docs/design/salon-reviews-summary.md): the
/// average to one decimal (the salon's public rating), the count, and how
/// many reviews give each star — visible reviews only.
class ReviewSummary extends Equatable {
  const ReviewSummary({
    required this.average,
    required this.count,
    this.distribution = const {5: 0, 4: 0, 3: 0, 2: 0, 1: 0},
  });

  final double average;
  final int count;

  /// Star → reviews; every star 5 → 1 present.
  final Map<int, int> distribution;

  /// The wire keys are strings (`"5"`); a missing star is 0.
  factory ReviewSummary.fromJson(Map<String, dynamic> json) {
    final raw = (json['distribution'] as Map?) ?? const {};
    return ReviewSummary(
      average: (json['average'] as num? ?? 0).toDouble(),
      count: (json['count'] as num? ?? 0).toInt(),
      distribution: {
        for (final star in const [5, 4, 3, 2, 1])
          star: (raw['$star'] as num? ?? 0).toInt(),
      },
    );
  }

  @override
  List<Object?> get props => [average, count, distribution];
}

/// One page of the salon's reviews, with the whole salon's card.
class MyReviews {
  const MyReviews({required this.items, required this.total, this.summary});

  final List<Review> items;
  final int total;

  /// Absent from a server older than it — the screen then uses the page.
  final ReviewSummary? summary;
}
