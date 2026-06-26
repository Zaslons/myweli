import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../reviews_repository.dart';

/// Postgres-backed [ReviewsRepository] (table `reviews`, migration `0007`).
class PostgresReviewsRepository implements ReviewsRepository {
  PostgresReviewsRepository(this._pool);

  final Pool<void> _pool;

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
        'SELECT * FROM reviews WHERE provider_id = @pid '
        'ORDER BY created_at DESC LIMIT @lim OFFSET @off',
      ),
      parameters: {
        'pid': providerId,
        'lim': pageSize,
        'off': (page - 1) * pageSize,
      },
    );
    final count = await _pool.execute(
      Sql.named(
        'SELECT count(*)::int AS n FROM reviews WHERE provider_id = @pid',
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
        'SELECT * FROM reviews WHERE provider_id = @pid '
        'ORDER BY created_at DESC LIMIT @lim',
      ),
      parameters: {'pid': providerId, 'lim': limit},
    );
    return [for (final r in rows) _dto(r.toColumnMap())];
  }

  @override
  Future<RatingAgg> aggregateProvider(String providerId) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT COALESCE(AVG(rating), 0)::float8 AS avg, COUNT(*)::int AS n '
        'FROM reviews WHERE provider_id = @pid',
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
        'SELECT artist_id, AVG(rating)::float8 AS avg, COUNT(*)::int AS n '
        'FROM reviews WHERE provider_id = @pid AND artist_id IS NOT NULL '
        'GROUP BY artist_id',
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
}
