import 'package:postgres/postgres.dart';

import '../idempotency/idempotency_store.dart';

/// How long one idempotency statement may take before it is abandoned. The
/// same two seconds, for the same reason, as `kLimiterQueryTimeout`: the
/// helper fails open on an error (`idempotency/idempotent.dart`), and a
/// database that accepts the connection and never answers raises no error
/// without a deadline — the booking would wait for Cloud Run's 300 s.
const kIdempotencyQueryTimeout = Duration(seconds: 2);

/// Rows per prune statement, and how many statements one prune may issue —
/// the rate limiter's batching, for the same 2 s deadline.
const int kIdempotencyPruneBatchSize = 5000;
const int kIdempotencyPruneMaxBatches = 200;

/// Postgres-backed [IdempotencyStore] (table `idempotency_keys`, migration
/// `0040`). Shared across instances: a retry that lands on another instance
/// than the first answer still gets that answer replayed.
///
/// Design: docs/design/write-idempotency.md §3.
class PostgresIdempotencyStore implements IdempotencyStore {
  PostgresIdempotencyStore(this._pool, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Pool<void> _pool;

  /// Injected so the contract can age a row without waiting — every time
  /// below is computed from it, never from the database's `now()`.
  final DateTime Function() _now;

  Map<String, Object?> _where(String accountId, String route, String key) => {
    'a': accountId,
    'r': route,
    'k': key,
  };

  @override
  Future<IdempotencyClaim> claim({
    required String accountId,
    required String route,
    required String key,
    required String fingerprint,
  }) async {
    final now = _now().toUtc();
    // Two tries: the row seen as taken may be released between the upsert
    // and the read below; the second upsert then reserves it.
    for (var attempt = 0; attempt < 2; attempt++) {
      // **The reservation is ONE statement**, so two instances racing on the
      // same key cannot both win: the insert, or the take-over of an expired
      // or abandoned row, returns the row only to the one that wrote it.
      final reserved = await _pool.execute(
        Sql.named(
          'INSERT INTO idempotency_keys '
          '(account_id, route, key, fingerprint, created_at) '
          'VALUES (@a, @r, @k, @f, @now:timestamptz) '
          'ON CONFLICT (account_id, route, key) DO UPDATE SET '
          'fingerprint = EXCLUDED.fingerprint, '
          'created_at = EXCLUDED.created_at, status = NULL, body = NULL '
          'WHERE idempotency_keys.created_at <= @expired:timestamptz '
          'OR (idempotency_keys.status IS NULL '
          'AND idempotency_keys.created_at <= @abandoned:timestamptz) '
          'RETURNING 1',
        ),
        parameters: {
          ..._where(accountId, route, key),
          'f': fingerprint,
          'now': now,
          'expired': now.subtract(kIdempotencyWindow),
          'abandoned': now.subtract(kIdempotencyAbandonedAfter),
        },
        timeout: kIdempotencyQueryTimeout,
      );
      if (reserved.isNotEmpty) return const ClaimReserved();

      final rows = await _pool.execute(
        Sql.named(
          'SELECT fingerprint, status, body FROM idempotency_keys '
          'WHERE account_id = @a AND route = @r AND key = @k',
        ),
        parameters: _where(accountId, route, key),
        timeout: kIdempotencyQueryTimeout,
      );
      if (rows.isEmpty) continue;
      final row = rows.first.toColumnMap();
      if (row['fingerprint'] != fingerprint) return const ClaimMismatch();
      final status = row['status'] as int?;
      if (status == null) return const ClaimInProgress();
      return ClaimReplay(status: status, body: row['body']! as String);
    }
    return const ClaimInProgress();
  }

  @override
  Future<void> complete({
    required String accountId,
    required String route,
    required String key,
    required int status,
    required String body,
  }) async {
    await _pool.execute(
      Sql.named(
        'UPDATE idempotency_keys SET status = @s, body = @b '
        'WHERE account_id = @a AND route = @r AND key = @k '
        'AND status IS NULL',
      ),
      parameters: {..._where(accountId, route, key), 's': status, 'b': body},
      timeout: kIdempotencyQueryTimeout,
    );
  }

  @override
  Future<void> release({
    required String accountId,
    required String route,
    required String key,
  }) async {
    await _pool.execute(
      Sql.named(
        'DELETE FROM idempotency_keys '
        'WHERE account_id = @a AND route = @r AND key = @k '
        'AND status IS NULL',
      ),
      parameters: _where(accountId, route, key),
      timeout: kIdempotencyQueryTimeout,
    );
  }

  /// Batched for the reason `PostgresRateLimiter.prune` is: each slice is its
  /// own statement under the 2 s deadline, so a backlog drains a slice at a
  /// time instead of timing out every day on a bigger table.
  @override
  Future<int> prune(Duration olderThan) async {
    final cutoff = _now().toUtc().subtract(olderThan);
    var total = 0;
    for (var batch = 0; batch < kIdempotencyPruneMaxBatches; batch++) {
      final r = await _pool.execute(
        Sql.named(
          'DELETE FROM idempotency_keys WHERE ctid = ANY(ARRAY('
          'SELECT ctid FROM idempotency_keys '
          'WHERE created_at < @cutoff:timestamptz '
          'LIMIT $kIdempotencyPruneBatchSize))',
        ),
        parameters: {'cutoff': cutoff},
        timeout: kIdempotencyQueryTimeout,
      );
      total += r.affectedRows;
      if (r.affectedRows < kIdempotencyPruneBatchSize) break;
    }
    return total;
  }

  @override
  Future<void> deleteForAccount(String accountId) async {
    await _pool.execute(
      Sql.named('DELETE FROM idempotency_keys WHERE account_id = @a'),
      parameters: {'a': accountId},
      timeout: kIdempotencyQueryTimeout,
    );
  }
}
