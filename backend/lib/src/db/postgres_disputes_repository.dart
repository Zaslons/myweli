import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';

import '../admin/disputes_repository.dart';

/// Postgres-backed dispute records (table `disputes`, migration `0014`).
class PostgresDisputesRepository implements DisputesRepository {
  PostgresDisputesRepository(this._pool);

  final Pool<void> _pool;
  final _rng = Random.secure();

  String _id() {
    final bytes = List<int>.generate(12, (_) => _rng.nextInt(256));
    return 'dispute_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  @override
  Future<Map<String, dynamic>> create({
    required String appointmentId,
    required String openedBy,
    required String reason,
  }) async {
    final rows = await _pool.execute(
      Sql.named(
        'INSERT INTO disputes (id, appointment_id, opened_by, reason) '
        'VALUES (@id, @appt, @by, @reason) RETURNING *',
      ),
      parameters: {
        'id': _id(),
        'appt': appointmentId,
        'by': openedBy,
        'reason': reason,
      },
    );
    return _dto(rows.first.toColumnMap());
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> list({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final where = status != null ? 'WHERE status = @status' : '';
    final params = <String, Object?>{if (status != null) 'status': status};
    final count = await _pool.execute(
      Sql.named('SELECT COUNT(*)::int AS n FROM disputes $where'),
      parameters: params,
    );
    final rows = await _pool.execute(
      Sql.named(
        'SELECT * FROM disputes $where '
        'ORDER BY created_at DESC LIMIT @ps OFFSET @off',
      ),
      parameters: {...params, 'ps': pageSize, 'off': (page - 1) * pageSize},
    );
    return (
      items: rows.map((r) => _dto(r.toColumnMap())).toList(),
      total: count.first.toColumnMap()['n'] as int,
    );
  }

  @override
  Future<Map<String, dynamic>?> byId(String id) async {
    final rows = await _pool.execute(
      Sql.named('SELECT * FROM disputes WHERE id = @id'),
      parameters: {'id': id},
    );
    if (rows.isEmpty) return null;
    return _dto(rows.first.toColumnMap());
  }

  @override
  Future<Map<String, dynamic>?> resolve(
    String id, {
    required String resolution,
    required String resolvedBy,
  }) async {
    final rows = await _pool.execute(
      Sql.named(
        "UPDATE disputes SET status = 'resolved', resolution = @r, "
        'resolved_by = @by, resolved_at = now() WHERE id = @id RETURNING *',
      ),
      parameters: {'id': id, 'r': resolution, 'by': resolvedBy},
    );
    if (rows.isEmpty) return null;
    return _dto(rows.first.toColumnMap());
  }

  Map<String, dynamic> _dto(Map<String, dynamic> m) => {
    'id': m['id'],
    'appointmentId': m['appointment_id'],
    'openedBy': m['opened_by'],
    'status': m['status'],
    'reason': m['reason'],
    'resolution': m['resolution'],
    'createdAt': (m['created_at'] as DateTime).toIso8601String(),
    'resolvedBy': m['resolved_by'],
    'resolvedAt': (m['resolved_at'] as DateTime?)?.toIso8601String(),
  };
}
