import 'package:postgres/postgres.dart';

import '../notifications/notification_prefs_repository.dart';

/// Postgres-backed notification preferences (table `notification_preferences`,
/// migration `0019`). Absent row → all-true defaults; writes upsert-merge only
/// the provided fields. Design: docs/design/notification-preferences.md.
class PostgresNotificationPrefsRepository
    implements NotificationPrefsRepository {
  PostgresNotificationPrefsRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<NotificationPrefs> get(String userId) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT reminders, marketing, push FROM notification_preferences '
        'WHERE user_id = @u',
      ),
      parameters: {'u': userId},
    );
    if (rows.isEmpty) return const NotificationPrefs();
    return _dto(rows.first.toColumnMap());
  }

  @override
  Future<NotificationPrefs> update(
    String userId, {
    bool? reminders,
    bool? marketing,
    bool? push,
  }) async {
    final rows = await _pool.execute(
      Sql.named('''
INSERT INTO notification_preferences (user_id, reminders, marketing, push, updated_at)
VALUES (@u, COALESCE(@r::boolean, true), COALESCE(@m::boolean, true), COALESCE(@p::boolean, true), now())
ON CONFLICT (user_id) DO UPDATE SET
  reminders = COALESCE(@r::boolean, notification_preferences.reminders),
  marketing = COALESCE(@m::boolean, notification_preferences.marketing),
  push = COALESCE(@p::boolean, notification_preferences.push),
  updated_at = now()
RETURNING reminders, marketing, push'''),
      parameters: {'u': userId, 'r': reminders, 'm': marketing, 'p': push},
    );
    return _dto(rows.first.toColumnMap());
  }

  NotificationPrefs _dto(Map<String, dynamic> m) => NotificationPrefs(
    reminders: m['reminders'] as bool,
    marketing: m['marketing'] as bool,
    push: m['push'] as bool,
  );
}
