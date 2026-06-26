import 'package:postgres/postgres.dart';

import '../favorites_repository.dart';

/// Postgres-backed [FavoritesRepository] (table `favorites`, migration `0006`).
class PostgresFavoritesRepository implements FavoritesRepository {
  PostgresFavoritesRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<List<String>> listForUser(String userId) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT provider_id FROM favorites WHERE user_id = @uid '
        'ORDER BY created_at DESC',
      ),
      parameters: {'uid': userId},
    );
    return [for (final r in rows) r.toColumnMap()['provider_id'] as String];
  }

  @override
  Future<void> add(String userId, String providerId) async {
    await _pool.execute(
      Sql.named(
        'INSERT INTO favorites (user_id, provider_id) VALUES (@uid, @pid) '
        'ON CONFLICT (user_id, provider_id) DO NOTHING',
      ),
      parameters: {'uid': userId, 'pid': providerId},
    );
  }

  @override
  Future<void> remove(String userId, String providerId) async {
    await _pool.execute(
      Sql.named(
        'DELETE FROM favorites WHERE user_id = @uid AND provider_id = @pid',
      ),
      parameters: {'uid': userId, 'pid': providerId},
    );
  }
}
