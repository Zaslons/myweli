import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';

import '../admin/audit_log_repository.dart';

/// Postgres-backed append-only audit log.
class PostgresAuditLogRepository implements AuditLogRepository {
  PostgresAuditLogRepository(this._pool);

  final Pool<void> _pool;
  final _rng = Random.secure();

  String _id() {
    final bytes = List<int>.generate(12, (_) => _rng.nextInt(256));
    return 'audit_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  @override
  Future<void> append(AuditEntry entry) async {
    await _pool.execute(
      Sql.named(
        'INSERT INTO audit_log '
        '(id, actor_admin_id, action, target_type, target_id, reason, metadata) '
        'VALUES (@id, @actor, @action, @tt, @ti, @reason, @meta:jsonb)',
      ),
      parameters: {
        'id': _id(),
        'actor': entry.actorAdminId,
        'action': entry.action,
        'tt': entry.targetType,
        'ti': entry.targetId,
        'reason': entry.reason,
        'meta': jsonEncode(entry.metadata),
      },
    );
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> list({
    int page = 1,
    int pageSize = 20,
    String? actor,
    String? action,
  }) async {
    final where = <String>[];
    final params = <String, dynamic>{};
    if (actor != null) {
      where.add('actor_admin_id = @actor');
      params['actor'] = actor;
    }
    if (action != null) {
      where.add('action = @action');
      params['action'] = action;
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final count = await _pool.execute(
      Sql.named('SELECT COUNT(*)::int FROM audit_log $clause'),
      parameters: params,
    );
    final total = count.first[0]! as int;

    final rows = await _pool.execute(
      Sql.named(
        'SELECT id, actor_admin_id, action, target_type, target_id, reason, '
        'metadata, created_at FROM audit_log $clause '
        'ORDER BY created_at DESC LIMIT @ps OFFSET @off',
      ),
      parameters: {...params, 'ps': pageSize, 'off': (page - 1) * pageSize},
    );

    return (
      items: rows.map((r) {
        final meta = r[6];
        return {
          'id': r[0],
          'actorAdminId': r[1],
          'action': r[2],
          'targetType': r[3],
          'targetId': r[4],
          'reason': r[5],
          'metadata': meta is String ? jsonDecode(meta) : meta,
          'createdAt': (r[7]! as DateTime).toUtc().toIso8601String(),
        };
      }).toList(),
      total: total,
    );
  }
}
