import 'package:postgres/postgres.dart';

import '../messaging/messaging_prefs_repository.dart';

/// Postgres-backed promotional opt-out (table `messaging_opt_out`, migration
/// `0015`). Design: docs/design/messaging-notifications.md §5.
class PostgresMessagingPrefsRepository implements MessagingPrefsRepository {
  PostgresMessagingPrefsRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<void> setOptedOut(String phone, bool optedOut) async {
    await _pool.execute(
      Sql.named(
        'INSERT INTO messaging_opt_out (phone, opted_out, updated_at) '
        'VALUES (@p, @v, now()) ON CONFLICT (phone) DO UPDATE '
        'SET opted_out = @v, updated_at = now()',
      ),
      parameters: {'p': phone, 'v': optedOut},
    );
  }

  @override
  Future<bool> isOptedOut(String phone) async {
    final rows = await _pool.execute(
      Sql.named('SELECT opted_out FROM messaging_opt_out WHERE phone = @p'),
      parameters: {'p': phone},
    );
    if (rows.isEmpty) return false;
    return rows.first.toColumnMap()['opted_out'] as bool;
  }
}
