import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';

import '../reviews_repository.dart';

/// Postgres-backed [ReviewsRepository] (table `reviews`, migration `0007`;
/// moderation in `0011`).
class PostgresReviewsRepository implements ReviewsRepository {
  PostgresReviewsRepository(this._pool);

  final Pool<void> _pool;
  final _rng = Random.secure();

  @override
  Future<void> upsertByAppointment(Map<String, dynamic> review) async {
    await _pool.execute(
      Sql.named('''
INSERT INTO reviews (id, appointment_id, provider_id, user_id, user_name,
  rating, text, verified, artist_id, artist_name, service_name, photo_urls,
  created_at)
VALUES (@id, @appt, @pid, @uid, @uname, @rating, @text, @verified, @aid,
  @aname, @sname, @photos:jsonb, @createdAt)
ON CONFLICT (appointment_id) DO UPDATE SET
  rating = EXCLUDED.rating, text = EXCLUDED.text, verified = EXCLUDED.verified,
  artist_id = EXCLUDED.artist_id, artist_name = EXCLUDED.artist_name,
  service_name = EXCLUDED.service_name, photo_urls = EXCLUDED.photo_urls,
  created_at = EXCLUDED.created_at'''),
      parameters: {
        'id': review['id'],
        'appt': review['appointmentId'],
        'pid': review['providerId'],
        'uid': review['userId'],
        'uname': review['userName'],
        'rating': (review['rating'] as num).toInt(),
        'text': review['text'] ?? '',
        'verified': review['verified'] ?? true,
        'aid': review['artistId'],
        'aname': review['artistName'],
        'sname': review['serviceName'] ?? '',
        'photos': jsonEncode(review['photoUrls'] ?? const <String>[]),
        'createdAt': DateTime.parse(review['createdAt'] as String),
      },
    );
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> listForProvider(
    String providerId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final rows = await _pool.execute(
      Sql.named(
        "SELECT * FROM reviews WHERE provider_id = @pid "
        "AND moderation_status <> 'hidden' "
        "ORDER BY created_at DESC LIMIT @lim OFFSET @off",
      ),
      parameters: {
        'pid': providerId,
        'lim': pageSize,
        'off': (page - 1) * pageSize,
      },
    );
    final count = await _pool.execute(
      Sql.named(
        "SELECT count(*)::int AS n FROM reviews WHERE provider_id = @pid "
        "AND moderation_status <> 'hidden'",
      ),
      parameters: {'pid': providerId},
    );
    return (
      items: [for (final r in rows) _dto(r.toColumnMap())],
      total: (count.first.toColumnMap()['n'] as int),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> recentForProvider(
    String providerId,
    int limit,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        "SELECT * FROM reviews WHERE provider_id = @pid "
        "AND moderation_status <> 'hidden' "
        "ORDER BY created_at DESC LIMIT @lim",
      ),
      parameters: {'pid': providerId, 'lim': limit},
    );
    return [for (final r in rows) _dto(r.toColumnMap())];
  }

  @override
  Future<RatingAgg> aggregateProvider(String providerId) async {
    final rows = await _pool.execute(
      Sql.named(
        "SELECT COALESCE(AVG(rating), 0)::float8 AS avg, COUNT(*)::int AS n "
        "FROM reviews WHERE provider_id = @pid "
        "AND moderation_status <> 'hidden'",
      ),
      parameters: {'pid': providerId},
    );
    final m = rows.first.toColumnMap();
    return (rating: (m['avg'] as num).toDouble(), count: m['n'] as int);
  }

  @override
  Future<Map<String, RatingAgg>> aggregateByArtist(String providerId) async {
    final rows = await _pool.execute(
      Sql.named(
        "SELECT artist_id, AVG(rating)::float8 AS avg, COUNT(*)::int AS n "
        "FROM reviews WHERE provider_id = @pid AND artist_id IS NOT NULL "
        "AND moderation_status <> 'hidden' "
        "GROUP BY artist_id",
      ),
      parameters: {'pid': providerId},
    );
    return {
      for (final r in rows)
        (r.toColumnMap()['artist_id'] as String): (
          rating: (r.toColumnMap()['avg'] as num).toDouble(),
          count: r.toColumnMap()['n'] as int,
        ),
    };
  }

  Map<String, dynamic> _dto(Map<String, dynamic> m) {
    final photos = m['photo_urls'];
    return {
      'id': m['id'],
      'appointmentId': m['appointment_id'],
      'providerId': m['provider_id'],
      'userId': m['user_id'],
      'userName': m['user_name'],
      'rating': (m['rating'] as num).toInt(),
      'text': m['text'],
      'verified': m['verified'],
      'artistId': m['artist_id'],
      'artistName': m['artist_name'],
      'serviceName': m['service_name'],
      'photoUrls': photos is String
          ? jsonDecode(photos)
          : (photos ?? <String>[]),
      'createdAt': (m['created_at'] as DateTime).toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>?> reviewById(String id) async {
    final rows = await _pool.execute(
      Sql.named('SELECT * FROM reviews WHERE id = @id'),
      parameters: {'id': id},
    );
    if (rows.isEmpty) return null;
    return _dto(rows.first.toColumnMap());
  }

  @override
  Future<void> addReport(
    String reviewId,
    String reporterUserId,
    String reason,
  ) async {
    await _pool.execute(
      Sql.named(
        'INSERT INTO review_reports (id, review_id, reporter_user_id, reason) '
        'VALUES (@id, @rid, @uid, @reason) '
        'ON CONFLICT (review_id, reporter_user_id) DO NOTHING',
      ),
      parameters: {
        'id': _reportId(),
        'rid': reviewId,
        'uid': reporterUserId,
        'reason': reason,
      },
    );
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> listReportedReviews({
    int page = 1,
    int pageSize = 20,
  }) async {
    final count = await _pool.execute(
      Sql.named(
        "SELECT COUNT(DISTINCT review_id)::int AS n "
        "FROM review_reports WHERE status = 'open'",
      ),
    );
    final total = count.first.toColumnMap()['n'] as int;
    final rows = await _pool.execute(
      Sql.named('''
SELECT r.id AS review_id, r.provider_id, r.user_name, r.rating, r.text,
  r.moderation_status,
  rep.report_count, rep.last_reason, rep.last_reported_at
FROM reviews r
JOIN (
  SELECT review_id, COUNT(*)::int AS report_count,
    (array_agg(reason ORDER BY created_at DESC))[1] AS last_reason,
    MAX(created_at) AS last_reported_at
  FROM review_reports WHERE status = 'open'
  GROUP BY review_id
) rep ON rep.review_id = r.id
ORDER BY rep.last_reported_at DESC
LIMIT @lim OFFSET @off'''),
      parameters: {'lim': pageSize, 'off': (page - 1) * pageSize},
    );
    return (
      items: rows.map((row) {
        final m = row.toColumnMap();
        return {
          'reviewId': m['review_id'],
          'providerId': m['provider_id'],
          'userName': m['user_name'],
          'rating': (m['rating'] as num).toInt(),
          'text': m['text'],
          'moderationStatus': m['moderation_status'],
          'reportCount': m['report_count'],
          'lastReason': m['last_reason'],
          'lastReportedAt': (m['last_reported_at'] as DateTime)
              .toIso8601String(),
        };
      }).toList(),
      total: total,
    );
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> listHidden({
    int page = 1,
    int pageSize = 20,
  }) async {
    final count = await _pool.execute(
      Sql.named(
        "SELECT COUNT(*)::int AS n FROM reviews "
        "WHERE moderation_status = 'hidden'",
      ),
    );
    final rows = await _pool.execute(
      Sql.named(
        "SELECT * FROM reviews WHERE moderation_status = 'hidden' "
        "ORDER BY created_at DESC LIMIT @ps OFFSET @off",
      ),
      parameters: {'ps': pageSize, 'off': (page - 1) * pageSize},
    );
    return (
      items: [for (final r in rows) _dto(r.toColumnMap())],
      total: count.first.toColumnMap()['n'] as int,
    );
  }

  @override
  Future<Map<String, dynamic>?> setModerationStatus(
    String reviewId,
    String status,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        'UPDATE reviews SET moderation_status = @s WHERE id = @id RETURNING *',
      ),
      parameters: {'id': reviewId, 's': status},
    );
    if (rows.isEmpty) return null;
    return _dto(rows.first.toColumnMap());
  }

  @override
  Future<void> resolveReports(String reviewId, String resolvedBy) async {
    await _pool.execute(
      Sql.named(
        "UPDATE review_reports SET status = 'resolved', resolved_by = @by, "
        "resolved_at = now() WHERE review_id = @rid AND status = 'open'",
      ),
      parameters: {'rid': reviewId, 'by': resolvedBy},
    );
  }

  String _reportId() {
    final bytes = List<int>.generate(12, (_) => _rng.nextInt(256));
    return 'report_${base64Url.encode(bytes).replaceAll('=', '')}';
  }
}
