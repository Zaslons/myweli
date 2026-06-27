import 'dart:math';

/// Per-consumer in-app notification feed (map DTOs, mirroring the app's
/// `AppNotification`). All reads/writes are **scoped by `userId`**. Design:
/// docs/design/notification-center.md.
abstract interface class NotificationsRepository {
  /// Append a notification for [userId]; returns the stored row.
  Future<Map<String, dynamic>> add({
    required String userId,
    required String type,
    required String title,
    required String body,
    String? route,
  });

  /// The user's latest notifications, newest first (capped by [limit]).
  Future<List<Map<String, dynamic>>> listForUser(String userId, {int limit});

  /// Mark one read; false if it isn't the user's / doesn't exist.
  Future<bool> markRead(String userId, String id);

  /// Mark all the user's notifications read.
  Future<void> markAllRead(String userId);
}

class InMemoryNotificationsRepository implements NotificationsRepository {
  final List<Map<String, dynamic>> _rows = [];
  final _rng = Random();

  String _id() =>
      'notif_${DateTime.now().microsecondsSinceEpoch}_${_rng.nextInt(1 << 32)}';

  @override
  Future<Map<String, dynamic>> add({
    required String userId,
    required String type,
    required String title,
    required String body,
    String? route,
  }) async {
    final row = {
      'id': _id(),
      'userId': userId,
      'type': type,
      'title': title,
      'body': body,
      'route': route,
      'read': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    _rows.add(row);
    return row;
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    int limit = 50,
  }) async {
    final mine = _rows.where((r) => r['userId'] == userId).toList()
      ..sort(
        (a, b) =>
            (b['createdAt'] as String).compareTo(a['createdAt'] as String),
      );
    return mine.take(limit).toList();
  }

  @override
  Future<bool> markRead(String userId, String id) async {
    for (final r in _rows) {
      if (r['id'] == id && r['userId'] == userId) {
        r['read'] = true;
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> markAllRead(String userId) async {
    for (final r in _rows) {
      if (r['userId'] == userId) r['read'] = true;
    }
  }
}
