import 'package:postgres/postgres.dart';

import '../auth/apple_tokens.dart';

/// Postgres-backed Sign in with Apple refresh tokens (table `apple_tokens`,
/// migration `0042`). B6.7 — docs/design/backend-integrity-batch6.md §13.
class PostgresAppleTokenRepository implements AppleTokenRepository {
  PostgresAppleTokenRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<void> keep({
    required String kind,
    required String accountId,
    required String clientId,
    required String refreshToken,
  }) async {
    await _pool.execute(
      Sql.named(
        'INSERT INTO apple_tokens '
        '(account_kind, account_id, client_id, refresh_token, created_at) '
        'VALUES (@k, @a, @c, @t, now()) '
        'ON CONFLICT (account_kind, account_id, client_id) DO UPDATE SET '
        'refresh_token = EXCLUDED.refresh_token, created_at = now()',
      ),
      parameters: {'k': kind, 'a': accountId, 'c': clientId, 't': refreshToken},
    );
  }

  @override
  Future<List<AppleToken>> listFor({
    required String kind,
    required String accountId,
  }) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT client_id, refresh_token FROM apple_tokens '
        'WHERE account_kind = @k AND account_id = @a',
      ),
      parameters: {'k': kind, 'a': accountId},
    );
    return [
      for (final r in rows)
        (
          clientId: r.toColumnMap()['client_id'] as String,
          refreshToken: r.toColumnMap()['refresh_token'] as String,
        ),
    ];
  }

  @override
  Future<void> deleteFor({
    required String kind,
    required String accountId,
  }) async {
    await _pool.execute(
      Sql.named(
        'DELETE FROM apple_tokens WHERE account_kind = @k AND account_id = @a',
      ),
      parameters: {'k': kind, 'a': accountId},
    );
  }
}
