import 'package:postgres/postgres.dart';

import '../push/device_token_repository.dart';

/// Postgres-backed device-token registry (table `device_tokens`, migration
/// `0017`). Design: docs/design/push-notifications-fcm.md §4.
class PostgresDeviceTokenRepository implements DeviceTokenRepository {
  PostgresDeviceTokenRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<void> upsert({
    required String token,
    required String userId,
    required String role,
    required String platform,
  }) async {
    await _pool.execute(
      Sql.named(
        'INSERT INTO device_tokens (token, user_id, role, platform, updated_at) '
        'VALUES (@t, @u, @r, @p, now()) ON CONFLICT (token) DO UPDATE SET '
        'user_id = @u, role = @r, platform = @p, updated_at = now()',
      ),
      parameters: {'t': token, 'u': userId, 'r': role, 'p': platform},
    );
  }

  @override
  Future<List<String>> tokensForUser(String userId) async {
    final rows = await _pool.execute(
      Sql.named('SELECT token FROM device_tokens WHERE user_id = @u'),
      parameters: {'u': userId},
    );
    return rows.map((r) => r.toColumnMap()['token'] as String).toList();
  }

  @override
  Future<void> removeForUser(String userId, String token) async {
    await _pool.execute(
      Sql.named('DELETE FROM device_tokens WHERE token = @t AND user_id = @u'),
      parameters: {'t': token, 'u': userId},
    );
  }

  @override
  Future<void> remove(String token) async {
    await _pool.execute(
      Sql.named('DELETE FROM device_tokens WHERE token = @t'),
      parameters: {'t': token},
    );
  }
}
