import 'package:postgres/postgres.dart';

import '../security/rate_limiter.dart';

/// Postgres-backed [RateLimiter] (table `identity_rate_limits`, migration
/// `0034`).
///
/// Design: docs/design/backend-identity-rate-limits.md
/// How long a limiter query may take before it is abandoned.
///
/// **Failing open means failing FAST, and without this it did neither.**
/// `FailOpenRateLimiter` catches an error and lets the request through, so a
/// limiter blip costs a temporarily absent ceiling rather than a booking nobody
/// can make. That reasoning holds only if the query actually ERRORS.
///
/// Neither `PoolSettings` nor these calls set a deadline, so a database that
/// accepts the connection and then never answers — a wedged instance, a network
/// black hole, an upstream pool exhausted — produced no error at all. The future
/// simply never completed, the request sat until **Cloud Run's 300 second**
/// deadline killed it, and the caller waited five minutes for a booking.
///
/// Worse for the thing watching: `rate_limit_unavailable` is printed in that
/// catch, so in the wedged case the line was never printed and **"A per-identity
/// limit could NOT be enforced" could not fire in the one scenario it exists
/// for.**
///
/// Two seconds is far beyond any healthy single-row upsert on an indexed primary
/// key and far below anything a person would wait for. A pool-wide
/// `queryTimeout` was the tempting fix and is the wrong one: it also bounds
/// `withSchemaLock`, whose advisory-lock wait is SUPPOSED to wait
/// (docs/design/backend-migration-timeouts.md).
const kLimiterQueryTimeout = Duration(seconds: 2);

class PostgresRateLimiter implements RateLimiter {
  PostgresRateLimiter(this._pool);

  final Pool<void> _pool;

  @override
  Future<RateVerdict> hit(
    String bucket, {
    required int limit,
    required Duration window,
  }) async {
    // **One statement, and that is the point.** A read-then-write would race
    // across instances: two of them both read 9 against a limit of 10, both
    // decide there is room, and both proceed. The upsert increments and returns
    // the post-increment value in a single atomic step, so the Nth caller —
    // whichever instance it lands on — is the one that sees N.
    //
    // The same shape as `PostgresSendBudget`, deliberately duplicated rather
    // than shared: that table shipped to production and migrations here are
    // forward-only, so renaming what it queries would break every OTP email on
    // a rollback. If a THIRD counter appears, that is when to extract a shared
    // windowed counter.
    final rows = await _pool.execute(
      Sql.named(
        'INSERT INTO identity_rate_limits (bucket, window_start, hits) '
        'VALUES (@b, @w, 1) '
        'ON CONFLICT (bucket, window_start) '
        'DO UPDATE SET hits = identity_rate_limits.hits + 1 '
        'RETURNING hits',
      ),
      parameters: {'b': bucket, 'w': windowStart(DateTime.now(), window)},
      timeout: kLimiterQueryTimeout,
    );
    final hits = rows.first.toColumnMap()['hits'] as int;
    return (ok: hits <= limit, hits: hits, limit: limit);
  }

  @override
  Future<int> used(String bucket, {required Duration window}) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT hits FROM identity_rate_limits '
        'WHERE bucket = @b AND window_start = @w',
      ),
      parameters: {'b': bucket, 'w': windowStart(DateTime.now(), window)},
      timeout: kLimiterQueryTimeout,
    );
    if (rows.isEmpty) return 0;
    return rows.first.toColumnMap()['hits'] as int;
  }
}
