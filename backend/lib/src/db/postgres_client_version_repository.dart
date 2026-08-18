import 'package:postgres/postgres.dart';

import '../client_version/client_version_repository.dart';

/// Postgres-backed [ClientVersionRepository] (table `client_version_floors`,
/// migration `0032`).
///
/// **Read per request, never cached in a field.** `LocalitiesService` caches its
/// tree with no TTL and no invalidation, which is fine for geography and wrong
/// here: the whole value of this lever is how fast it takes effect, and with
/// `maxScale: 4` a cached floor could sit stale on three instances after the
/// admin has already changed it. A single-row primary-key lookup on a
/// four-row table is not worth optimising away.
class PostgresClientVersionRepository implements ClientVersionRepository {
  PostgresClientVersionRepository(this._pool);

  final Pool<void> _pool;

  static const _columns =
      'app_id, platform, minimum_build, recommended_build, update_url';

  ClientVersionFloor _map(Map<String, dynamic> m) => (
    appId: m['app_id'] as String,
    platform: m['platform'] as String,
    minimumBuild: m['minimum_build'] as int,
    recommendedBuild: m['recommended_build'] as int,
    updateUrl: m['update_url'] as String?,
  );

  @override
  Future<ClientVersionFloor?> floor(String appId, String platform) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT $_columns FROM client_version_floors '
        'WHERE app_id = @app AND platform = @plat',
      ),
      parameters: {'app': appId, 'plat': platform},
    );
    if (rows.isEmpty) return null;
    return _map(rows.first.toColumnMap());
  }

  @override
  Future<List<ClientVersionFloor>> all() async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT $_columns FROM client_version_floors ORDER BY app_id, platform',
      ),
    );
    return [for (final r in rows) _map(r.toColumnMap())];
  }

  @override
  Future<ClientVersionFloor?> setFloor(
    String appId,
    String platform, {
    required int minimumBuild,
    required int recommendedBuild,
    String? updateUrl,
  }) async {
    // UPDATE, never UPSERT: the four pairs come from the migration and are a
    // property of what we ship. A typo'd app_id must return not_found rather
    // than quietly create a row that governs nothing.
    final rows = await _pool.execute(
      Sql.named(
        'UPDATE client_version_floors SET minimum_build = @min, '
        'recommended_build = @rec, update_url = @url, updated_at = now() '
        'WHERE app_id = @app AND platform = @plat '
        'RETURNING $_columns',
      ),
      parameters: {
        'app': appId,
        'plat': platform,
        'min': minimumBuild,
        'rec': recommendedBuild,
        'url': updateUrl,
      },
    );
    if (rows.isEmpty) return null;
    return _map(rows.first.toColumnMap());
  }
}
