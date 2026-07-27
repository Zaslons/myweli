import 'privacy/anonymized_identity.dart';

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

  // --- Moderation (admin) — design: docs/design/admin-console.md -------------
  // Public reads above (list/recent/aggregate) exclude `hidden` reviews.

  /// A single review (any moderation status), or null.
  Future<Map<String, dynamic>?> reviewById(String id);

  /// A consumer flags a review. Idempotent per (review, reporter).
  Future<void> addReport(String reviewId, String reporterUserId, String reason);

  /// Reviews with ≥1 open report (one row each: newest report first), paginated.
  Future<({List<Map<String, dynamic>> items, int total})> listReportedReviews({
    int page,
    int pageSize,
  });

  /// Admin: reviews currently `hidden` (for the "Avis masqués" / restore view),
  /// newest-first, paginated.
  Future<({List<Map<String, dynamic>> items, int total})> listHidden({
    int page,
    int pageSize,
  });

  /// Set a review's `moderation_status` (`hidden`/`visible`); returns the review
  /// (with `providerId` for rating recompute), or null if absent.
  Future<Map<String, dynamic>?> setModerationStatus(
    String reviewId,
    String status,
  );

  /// Resolve all open reports for a review (admin acted on it).
  Future<void> resolveReports(String reviewId, String resolvedBy);
  // ---- Privacy (L1 erasure) ------------------------------------------------

  /// Erase the reviewer, keep the review.
  ///
  /// The rating is a public aggregate the salon **earned** — deleting the row
  /// would silently re-score a business because a customer closed an account.
  /// So `user_name` becomes [anonymousClientLabel] and `user_id` becomes
  /// [deletedUserId] (a tombstone, never NULL — the column is `NOT NULL` and
  /// the shipped mobile model types it non-nullable).
  ///
  /// Reports filed BY this user are **deleted**, not tombstoned:
  /// `UNIQUE (review_id, reporter_user_id)` means two erased users who
  /// reported the same review would collide on a shared tombstone.
  /// Returns the **public** object keys of the photos it detached, so the
  /// caller can erase them. Without this the tombstone is defeated: photo URLs
  /// are `review/{userId}/{uuid}.{ext}` in the PUBLIC bucket
  /// (`upload_signing_service.dart:98`), so an erased reviewer's user id stays
  /// legible in the address bar — and all of their reviews across every salon
  /// can be grouped back together by prefix. The column that was tombstoned is
  /// not the only place the id lives.
  Future<List<String>> anonymizeUser(String userId);
}

class InMemoryReviewsRepository implements ReviewsRepository {
  final List<Map<String, dynamic>> _reviews = [];
  final List<Map<String, dynamic>> _reports = [];
  var _reportSeq = 0;

  static bool _visible(Map<String, dynamic> r) =>
      (r['moderationStatus'] ?? 'visible') != 'hidden';

  /// Provider's **visible** reviews, newest first (public reads hide moderated).
  List<Map<String, dynamic>> _forProvider(String providerId) {
    final list =
        _reviews
            .where((r) => r['providerId'] == providerId && _visible(r))
            .toList()
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

  @override
  Future<Map<String, dynamic>?> reviewById(String id) async {
    for (final r in _reviews) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  @override
  Future<void> addReport(
    String reviewId,
    String reporterUserId,
    String reason,
  ) async {
    final exists = _reports.any(
      (r) => r['reviewId'] == reviewId && r['reporterUserId'] == reporterUserId,
    );
    if (exists) return;
    _reports.add({
      'id': 'report_${_reportSeq++}',
      'reviewId': reviewId,
      'reporterUserId': reporterUserId,
      'reason': reason,
      'status': 'open',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> listReportedReviews({
    int page = 1,
    int pageSize = 20,
  }) async {
    // Group open reports by review, newest report first.
    final open = _reports.where((r) => r['status'] == 'open').toList()
      ..sort(
        (a, b) =>
            (b['createdAt'] as String).compareTo(a['createdAt'] as String),
      );
    final byReview = <String, Map<String, dynamic>>{};
    for (final rep in open) {
      final rid = rep['reviewId'] as String;
      final entry = byReview[rid];
      if (entry == null) {
        final review = _reviews.firstWhere(
          (r) => r['id'] == rid,
          orElse: () => <String, dynamic>{},
        );
        byReview[rid] = {
          'reviewId': rid,
          'providerId': review['providerId'],
          'userName': review['userName'],
          'rating': review['rating'],
          'text': review['text'],
          'moderationStatus': review['moderationStatus'] ?? 'visible',
          'reportCount': 1,
          'lastReason': rep['reason'],
          'lastReportedAt': rep['createdAt'],
        };
      } else {
        entry['reportCount'] = (entry['reportCount'] as int) + 1;
      }
    }
    final all = byReview.values.toList();
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <Map<String, dynamic>>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (items: items, total: all.length);
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> listHidden({
    int page = 1,
    int pageSize = 20,
  }) async {
    final all =
        _reviews.where((r) => r['moderationStatus'] == 'hidden').toList()..sort(
          (a, b) =>
              (b['createdAt'] as String).compareTo(a['createdAt'] as String),
        );
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <Map<String, dynamic>>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (items: items, total: all.length);
  }

  @override
  Future<Map<String, dynamic>?> setModerationStatus(
    String reviewId,
    String status,
  ) async {
    for (final r in _reviews) {
      if (r['id'] == reviewId) {
        r['moderationStatus'] = status;
        return r;
      }
    }
    return null;
  }

  @override
  Future<void> resolveReports(String reviewId, String resolvedBy) async {
    for (final r in _reports) {
      if (r['reviewId'] == reviewId && r['status'] == 'open') {
        r['status'] = 'resolved';
        r['resolvedBy'] = resolvedBy;
        r['resolvedAt'] = DateTime.now().toUtc().toIso8601String();
      }
    }
  }

  @override
  Future<List<String>> anonymizeUser(String userId) async {
    final photos = <String>[];
    for (final r in _reviews) {
      if (r['userId'] != userId) continue;
      final urls = r['photoUrls'];
      if (urls is List) photos.addAll(urls.whereType<String>());
      r['userName'] = anonymousClientLabel;
      r['userId'] = deletedUserId;
      // The review keeps its rating and its text — the salon earned those. The
      // PHOTOS are the person's own, and their URL carries the id.
      r['photoUrls'] = const <String>[];
    }
    _reports.removeWhere((r) => r['reporterUserId'] == userId);
    return photos;
  }
}
