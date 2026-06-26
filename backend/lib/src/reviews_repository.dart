/// Aggregate rating for a provider or artist.
typedef RatingAgg = ({double rating, int count});

/// Persisted reviews (map DTOs, like the rest of the repos). One per
/// appointment. In-memory now; a Postgres impl satisfies the same interface.
/// Design: docs/design/consumer-reviews.md.
abstract interface class ReviewsRepository {
  /// Insert or replace the review for its `appointmentId` (one per visit).
  Future<void> upsertByAppointment(Map<String, dynamic> review);

  /// A provider's reviews, newest first, paginated.
  Future<({List<Map<String, dynamic>> items, int total})> listForProvider(
    String providerId, {
    int page,
    int pageSize,
  });

  /// The provider's latest [limit] reviews (for the profile preview).
  Future<List<Map<String, dynamic>>> recentForProvider(
    String providerId,
    int limit,
  );

  /// Average rating + count across the provider's reviews.
  Future<RatingAgg> aggregateProvider(String providerId);

  /// Average rating + count per attributed `artistId` for the provider.
  Future<Map<String, RatingAgg>> aggregateByArtist(String providerId);
}

class InMemoryReviewsRepository implements ReviewsRepository {
  final List<Map<String, dynamic>> _reviews = [];

  List<Map<String, dynamic>> _forProvider(String providerId) {
    final list = _reviews.where((r) => r['providerId'] == providerId).toList()
      ..sort(
        (a, b) =>
            (b['createdAt'] as String).compareTo(a['createdAt'] as String),
      );
    return list;
  }

  @override
  Future<void> upsertByAppointment(Map<String, dynamic> review) async {
    _reviews.removeWhere((r) => r['appointmentId'] == review['appointmentId']);
    _reviews.add(Map<String, dynamic>.from(review));
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> listForProvider(
    String providerId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final all = _forProvider(providerId);
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <Map<String, dynamic>>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (items: items, total: all.length);
  }

  @override
  Future<List<Map<String, dynamic>>> recentForProvider(
    String providerId,
    int limit,
  ) async {
    final all = _forProvider(providerId);
    return all.take(limit).toList();
  }

  @override
  Future<RatingAgg> aggregateProvider(String providerId) async {
    final all = _forProvider(providerId);
    return _agg(all);
  }

  @override
  Future<Map<String, RatingAgg>> aggregateByArtist(String providerId) async {
    final byArtist = <String, List<Map<String, dynamic>>>{};
    for (final r in _forProvider(providerId)) {
      final aid = r['artistId'] as String?;
      if (aid != null) (byArtist[aid] ??= []).add(r);
    }
    return byArtist.map((id, rs) => MapEntry(id, _agg(rs)));
  }

  RatingAgg _agg(List<Map<String, dynamic>> rs) {
    if (rs.isEmpty) return (rating: 0, count: 0);
    final sum = rs.fold<int>(0, (s, r) => s + (r['rating'] as num).toInt());
    return (rating: sum / rs.length, count: rs.length);
  }
}
