import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';

import '../notifications/notifications_repository.dart';

/// Postgres-backed notification feed (table `notifications`, migration `0018`).
/// Design: docs/design/notification-center.md.
class PostgresNotificationsRepository implements NotificationsRepository {
  PostgresNotificationsRepository(this._pool);

  final Pool<void> _pool;
  final _rng = Random.secure();

  String _id() {
    final bytes = List<int>.generate(12, (_) => _rng.nextInt(256));
    return 'notif_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  @override
  Future<Map<String, dynamic>> add({
    required String userId,
    required String type,
    required String title,
    required String body,
    String? route,
  }) async {
    final rows = await _pool.execute(
      Sql.named(
        'INSERT INTO notifications (id, user_id, type, title, body, route) '
        'VALUES (@id, @u, @t, @title, @body, @route) RETURNING *',
      ),
      parameters: {
        'id': _id(),
        'u': userId,
        't': type,
        'title': title,
        'body': body,
        'route': route,
      },
    );
    return _dto(rows.first.toColumnMap());
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    int limit = 50,
  }) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT * FROM notifications WHERE user_id = @u '
        'ORDER BY created_at DESC LIMIT @lim',
      ),
      parameters: {'u': userId, 'lim': limit},
    );
    return rows.map((r) => _dto(r.toColumnMap())).toList();
  }

  @override
  Future<bool> markRead(String userId, String id) async {
    final rows = await _pool.execute(
      Sql.named(
        'UPDATE notifications SET read = true '
        'WHERE id = @id AND user_id = @u RETURNING id',
      ),
      parameters: {'id': id, 'u': userId},
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> markAllRead(String userId) async {
    await _pool.execute(
      Sql.named('UPDATE notifications SET read = true WHERE user_id = @u'),
      parameters: {'u': userId},
    );
  }

  Map<String, dynamic> _dto(Map<String, dynamic> m) => {
    'id': m['id'],
    'userId': m['user_id'],
    'type': m['type'],
    'title': m['title'],
    'body': m['body'],
    'route': m['route'],
    'read': m['read'],
    'createdAt': (m['created_at'] as DateTime).toIso8601String(),
  };
}
