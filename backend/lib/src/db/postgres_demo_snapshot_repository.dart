import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../demo/demo_snapshot_repository.dart';

/// Postgres half of the demo snapshot (table `demo_snapshot`, migration
/// 0036). `CHECK (id = 1)` in the schema makes the single-row-ness a
/// database fact; every write here is an upsert against that one row.
class PostgresDemoSnapshotRepository implements DemoSnapshotRepository {
  PostgresDemoSnapshotRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<void> capture({
    required String providerId,
    required Map<String, dynamic> doc,
    required DateTime capturedAt,
  }) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO demo_snapshot (id, provider_id, doc, captured_at, last_reset_at)
        VALUES (1, @p, @d, @c, @c)
        ON CONFLICT (id) DO UPDATE SET
          provider_id = @p, doc = @d, captured_at = @c, last_reset_at = @c
      '''),
      parameters: {'p': providerId, 'd': jsonEncode(doc), 'c': capturedAt},
    );
  }

  @override
  Future<DemoSnapshot?> read() async {
    final rows = await _pool.execute(
      'SELECT * FROM demo_snapshot WHERE id = 1',
    );
    if (rows.isEmpty) return null;
    final m = rows.first.toColumnMap();
    return (
      providerId: m['provider_id'] as String,
      doc:
          (m['doc'] is String ? jsonDecode(m['doc'] as String) : m['doc'])
              as Map<String, dynamic>,
      capturedAt: (m['captured_at'] as DateTime).toUtc(),
      lastResetAt: (m['last_reset_at'] as DateTime?)?.toUtc(),
    );
  }

  @override
  Future<void> markReset(DateTime at) async {
    await _pool.execute(
      Sql.named('UPDATE demo_snapshot SET last_reset_at = @a WHERE id = 1'),
      parameters: {'a': at},
    );
  }
}
