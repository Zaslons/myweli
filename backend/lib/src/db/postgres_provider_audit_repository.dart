import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';

import '../clients/provider_audit_log.dart';

/// Postgres-backed [ProviderAuditLogRepository] (table `provider_audit_log`,
/// migration `0024`). Append-only; `meta` is jsonb and never carries client
/// PII beyond the search query.
class PostgresProviderAuditLogRepository implements ProviderAuditLogRepository {
  PostgresProviderAuditLogRepository(this._pool);

  final Pool<void> _pool;
  final _random = Random();

  @override
  Future<void> log({
    required String providerId,
    required String actorAccountId,
    required String action,
    String? targetId,
    Map<String, dynamic> meta = const {},
  }) async {
    await _pool.execute(
      Sql.named(
        'INSERT INTO provider_audit_log '
        '(id, provider_id, actor_account_id, action, target_id, meta, '
        'created_at) '
        'VALUES (@id, @pid, @actor, @action, @target:text, @meta:jsonb, '
        'now())',
      ),
      parameters: {
        'id':
            'audit_${DateTime.now().microsecondsSinceEpoch}_'
            '${_random.nextInt(1 << 32)}',
        'pid': providerId,
        'actor': actorAccountId,
        'action': action,
        'target': targetId,
        // Raw map — the driver's jsonb codec encodes it (no double encode).
        'meta': meta,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> entriesFor(
    String providerId, {
    int limit = 100,
  }) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT * FROM provider_audit_log WHERE provider_id = @pid '
        'ORDER BY created_at DESC LIMIT @limit',
      ),
      parameters: {'pid': providerId, 'limit': limit},
    );
    return [
      for (final r in rows)
        (() {
          final m = r.toColumnMap();
          return {
            'id': m['id'],
            'providerId': m['provider_id'],
            'actorAccountId': m['actor_account_id'],
            'action': m['action'],
            'targetId': m['target_id'],
            'meta': switch (m['meta']) {
              final Map<String, dynamic> j => j,
              final String s => jsonDecode(s) as Map<String, dynamic>,
              _ => const <String, dynamic>{},
            },
            'createdAt': (m['created_at'] as DateTime)
                .toUtc()
                .toIso8601String(),
          };
        })(),
    ];
  }
}
