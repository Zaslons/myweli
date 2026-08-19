import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';

import '../auth/login_throttle.dart';

/// The admin-login lockout, shared across instances (table
/// `admin_login_throttle`, migration `0035`).
///
/// **Why this is not a `RateLimiter`.** A lockout is a penalty measured from an
/// event: after the Nth failure, refuse for a further T. A rate limit is a
/// budget measured from a clock: N per aligned window. They do not convert into
/// each other — five failures at 10:59:50 would be forgiven at 11:00:00 by an
/// hourly window, and that window's documented `2 x limit` boundary property
/// would hand out nine consecutive guesses against a budget of five. The
/// interface is also wrong in two further ways: it has no `reset` (and adding
/// one would put an attacker-callable budget refund on booking and uploads,
/// where nothing gates it), and its only decision-grade call increments, while
/// `isLocked` must be a pure read taken BEFORE bcrypt.
///
/// Design: docs/design/backend-admin-login-throttle.md
class PostgresLoginThrottle implements LoginThrottle {
  PostgresLoginThrottle(
    this._pool, {
    this.maxAttempts = kDefaultMaxAttempts,
    this.lockout = kDefaultLockout,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Pool<void> _pool;
  final int maxAttempts;
  final Duration lockout;
  final DateTime Function() _clock;

  /// SHA-256 of the normalised email — see the migration comment for why the
  /// address itself is never stored. Lowercase hex, matching Postgres's
  /// `encode(sha256(…::bytea), 'hex')` byte for byte, so the break-glass unlock
  /// in the runbook works.
  static String hashKey(String key) =>
      sha256.convert(utf8.encode(key)).toString();

  /// Locked iff a row says so at [now]. **A plain read, no write, no lock** —
  /// it runs before bcrypt on every login attempt.
  ///
  /// `>=`, not `>`: the in-memory original tested `now.isAfter(until)`, which
  /// leaves the boundary instant still locked. A sub-millisecond distinction
  /// that only a clock-pinned test can see, which is why there is one.
  ///
  /// It deliberately does NOT delete an expired row. The original's lazy delete
  /// is what zeroed the counter; here the same job is done by the expiry arm of
  /// [recordFailure], which keeps this path a single cheap primary-key lookup.
  @override
  Future<bool> isLocked(String key) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT 1 FROM admin_login_throttle '
        'WHERE key_hash = @k:text AND locked_until >= @now:timestamptz',
      ),
      parameters: {'k': hashKey(key), 'now': _clock().toUtc()},
    );
    return rows.isNotEmpty;
  }

  /// Counts one failure and locks once the count reaches [maxAttempts].
  ///
  /// **One statement, and three subtleties that each earn a test.**
  ///
  /// 1. `t.locked_until < @now` is the EXPIRED arm: a lock that has run out
  ///    restarts the counter at 1 and clears itself, reproducing the original's
  ///    lazy delete. Remove it and an admin is locked out permanently; invert it
  ///    and the counter resets on every failure so the lock never fires.
  /// 2. When `locked_until IS NULL` the comparison is NULL, `CASE WHEN NULL` is
  ///    not true, and control falls through to the ordinary increment. That
  ///    works BECAUSE of three-valued logic, not in spite of it — the obvious
  ///    "fix" of `COALESCE(t.locked_until, @now) < @now` silently breaks it.
  /// 3. The threshold reads `t.fail_count + 1`, the pre-increment value plus
  ///    one, because Postgres cannot reference another column's new value in the
  ///    same SET list. Repeating the first CASE inside the second is the mistake
  ///    to avoid.
  ///
  /// `RETURNING` is unused by the caller and taken anyway: it is what lets the
  /// concurrency test assert DISTINCT post-increment values rather than a final
  /// total, which a different mistake could also produce.
  @override
  Future<({int failCount, DateTime? lockedUntil})> recordFailure(
    String key,
  ) async {
    final now = _clock().toUtc();
    final rows = await _pool.execute(
      Sql.named(
        // **The types are annotated, and that is not decoration.** Without
        // them the driver infers `@until` from its position inside a CASE and
        // gets `text`, which Postgres rejects with 42804 against a
        // `timestamptz` column. Measured against a real server before anything
        // depended on this statement — the one genuine unknown in the design.
        'INSERT INTO admin_login_throttle AS t '
        '(key_hash, fail_count, locked_until, updated_at) '
        'VALUES (@k:text, 1, NULL, @now:timestamptz) '
        'ON CONFLICT (key_hash) DO UPDATE SET '
        'fail_count = CASE WHEN t.locked_until < @now:timestamptz THEN 1 '
        'ELSE t.fail_count + 1 END, '
        'locked_until = CASE WHEN t.locked_until < @now:timestamptz THEN NULL '
        'WHEN t.fail_count + 1 >= @max:int4 THEN @until:timestamptz '
        'ELSE NULL END, '
        'updated_at = @now:timestamptz '
        'RETURNING fail_count, locked_until',
      ),
      parameters: {
        'k': hashKey(key),
        'now': now,
        'max': maxAttempts,
        'until': now.add(lockout),
      },
    );
    final m = rows.first.toColumnMap();
    return (
      failCount: m['fail_count'] as int,
      lockedUntil: m['locked_until'] as DateTime?,
    );
  }

  /// Forgives everything for [key]. Called only after a SUCCESSFUL bcrypt, which
  /// is what makes it safe: the caller paid the credential to earn the refund.
  ///
  /// Without it, a wrong password on Monday and another on Friday accumulate
  /// toward a lockout across weeks.
  @override
  Future<void> reset(String key) => _pool.execute(
    Sql.named('DELETE FROM admin_login_throttle WHERE key_hash = @k:text'),
    parameters: {'k': hashKey(key)},
  );

  /// Deletes rows untouched for longer than [olderThan]; returns how many.
  ///
  /// **This is a security parameter, not housekeeping.** A `fail_count` whose
  /// `locked_until` is NULL never decays on its own, so without a prune four
  /// failures spread over a year would still be four. The prune window is
  /// therefore what gives the counter a decay, and it belongs beside
  /// [maxAttempts] and [lockout] rather than in a maintenance note.
  ///
  /// It also bounds the table, whose key set is open by design — unknown
  /// addresses are counted so that `locked_out` cannot become an
  /// admin-address oracle.
  Future<int> prune(Duration olderThan) async {
    final rows = await _pool.execute(
      Sql.named(
        'DELETE FROM admin_login_throttle WHERE updated_at < @cutoff:timestamptz '
        'RETURNING 1',
      ),
      parameters: {'cutoff': _clock().toUtc().subtract(olderThan)},
    );
    return rows.length;
  }
}
