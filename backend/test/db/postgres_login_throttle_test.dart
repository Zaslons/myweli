import 'dart:io';

import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_login_throttle.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// The admin-login lockout, against a real Postgres.
///
/// **Nothing here can be proven in memory.** The whole point of the move is
/// that four Cloud Run instances share one counter, and the SQL is what makes
/// that true — a `CASE` upsert whose behaviour depends on three-valued logic and
/// on Postgres refusing to see another column's new value. The in-memory twin
/// runs on a single-threaded event loop and would attest to none of it.
///
/// Design: docs/design/backend-admin-login-throttle.md
void main() {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    test(
      'postgres login throttle (skipped — set DATABASE_URL to run)',
      () {},
      skip: 'requires DATABASE_URL',
    );
    return;
  }

  late Pool<void> pool;
  var seq = 0;

  setUpAll(() async {
    pool = createPool(url);
    // Under the schema lock, as `dependencies.dart` does. `runMigrations` does
    // not take it itself, and a bare call races the other DB-gated files with
    // 23505 on `pg_type_typname_nsp_index`.
    await withSchemaLock(pool, () => runMigrations(pool));
  });

  tearDownAll(() async => pool.close());

  /// A key nothing else uses, so the suite is re-runnable against the same
  /// database without a reset.
  String freshKey() =>
      'probe-${DateTime.now().microsecondsSinceEpoch}-${seq++}';

  Future<Map<String, dynamic>?> row(String key) async {
    final r = await pool.execute(
      Sql.named(
        'SELECT fail_count, locked_until FROM admin_login_throttle '
        'WHERE key_hash = @k:text',
      ),
      parameters: {'k': PostgresLoginThrottle.hashKey(key)},
    );
    return r.isEmpty ? null : r.first.toColumnMap();
  }

  PostgresLoginThrottle throttleAt(DateTime Function() clock, {int max = 3}) =>
      PostgresLoginThrottle(
        pool,
        maxAttempts: max,
        lockout: const Duration(minutes: 15),
        clock: clock,
      );

  test('the table exists and migration 0035 applied', () async {
    final r = await pool.execute(
      Sql.named(
        "SELECT to_regclass('public.admin_login_throttle') IS NOT NULL AS ok",
      ),
    );
    expect(r.first.toColumnMap()['ok'], isTrue);
  });

  test('a fresh key inserts fail_count 1 and NO lock', () async {
    // Proves the NULL arm: `NULL < @now` is NULL, `CASE WHEN NULL` is not true,
    // so control falls through to the ordinary increment. The obvious "fix" of
    // COALESCE(locked_until, @now) would silently break this.
    final k = freshKey();
    final now = DateTime.utc(2026, 8, 19, 12);
    addTearDown(() => throttleAt(() => now).reset(k));
    final r = await throttleAt(() => now).recordFailure(k);
    expect(r.failCount, 1);
    expect(r.lockedUntil, isNull);
  });

  test('it locks AT the threshold, not one past it', () async {
    final k = freshKey();
    final now = DateTime.utc(2026, 8, 19, 12);
    final t = throttleAt(() => now);
    addTearDown(() => t.reset(k));
    expect((await t.recordFailure(k)).lockedUntil, isNull, reason: '1 of 3');
    expect((await t.recordFailure(k)).lockedUntil, isNull, reason: '2 of 3');
    final third = await t.recordFailure(k);
    expect(third.failCount, 3);
    expect(third.lockedUntil, isNotNull, reason: 'the 3rd of 3 locks');
    expect(await t.isLocked(k), isTrue);
  });

  test('the boundary instant is INSIDE the lock', () async {
    // The in-memory original tested `now.isAfter(until)`, so `now == until` is
    // still locked. A sub-millisecond distinction that only a pinned clock can
    // see — and the reason the SQL says `>=` rather than `>`.
    final k = freshKey();
    var now = DateTime.utc(2026, 8, 19, 12);
    final t = throttleAt(() => now);
    addTearDown(() => t.reset(k));
    for (var i = 0; i < 3; i++) {
      await t.recordFailure(k);
    }
    now = DateTime.utc(2026, 8, 19, 12, 15);
    expect(await t.isLocked(k), isTrue, reason: 'at exactly `until`');
    now = DateTime.utc(2026, 8, 19, 12, 15, 0, 1);
    expect(await t.isLocked(k), isFalse, reason: 'one millisecond later');
  });

  test('AFTER EXPIRY THE COUNTER RESTARTS AT 1', () async {
    // The expiry arm, which reproduces the in-memory lazy delete. Remove it and
    // an admin is locked out permanently; invert it and the counter resets on
    // every failure so the lock never fires. Nothing tested this before.
    final k = freshKey();
    var now = DateTime.utc(2026, 8, 19, 12);
    final t = throttleAt(() => now);
    addTearDown(() => t.reset(k));
    for (var i = 0; i < 3; i++) {
      await t.recordFailure(k);
    }
    now = DateTime.utc(2026, 8, 19, 12, 20); // past the lockout
    final after = await t.recordFailure(k);
    expect(after.failCount, 1, reason: 'a fresh count, not 4');
    expect(after.lockedUntil, isNull, reason: 'and not immediately re-locked');
    expect(await t.isLocked(k), isFalse);
  });

  test('reset deletes the row entirely', () async {
    final k = freshKey();
    final now = DateTime.utc(2026, 8, 19, 12);
    final t = throttleAt(() => now);
    await t.recordFailure(k);
    expect(await row(k), isNotNull);
    await t.reset(k);
    expect(await row(k), isNull, reason: 'count AND lock, not just the lock');
  });

  test(
    'CONCURRENT failures get distinct counts — the reason for the upsert',
    () async {
      // 25 statements in flight on one key. Under a read-then-write several would
      // read the same value and the count would land short. Distinctness is
      // asserted as well as the total, because a total of 25 could arrive from a
      // different mistake.
      final k = freshKey();
      final now = DateTime.utc(2026, 8, 19, 12);
      final t = throttleAt(() => now, max: 100);
      addTearDown(() => t.reset(k));
      final results = await Future.wait([
        for (var i = 0; i < 25; i++) t.recordFailure(k),
      ]);
      expect(
        results.map((r) => r.failCount).toSet(),
        hasLength(25),
        reason: 'every caller saw a DIFFERENT post-increment value',
      );
      expect((await row(k))!['fail_count'], 25);
    },
  );

  test('two keys are independent', () async {
    final a = freshKey();
    final b = freshKey();
    final now = DateTime.utc(2026, 8, 19, 12);
    final t = throttleAt(() => now);
    addTearDown(() => t.reset(a));
    addTearDown(() => t.reset(b));
    for (var i = 0; i < 3; i++) {
      await t.recordFailure(a);
    }
    expect(await t.isLocked(a), isTrue);
    expect(await t.isLocked(b), isFalse, reason: 'b is untouched');
  });

  test('the stored key is a hash, never the address', () async {
    // The table must not become a collection of third-party email addresses an
    // attacker chose, and every row must be the same width whatever was
    // submitted — the route has no length bound on `email`.
    const email = 'someone@example.test';
    final now = DateTime.utc(2026, 8, 19, 12);
    final t = throttleAt(() => now);
    addTearDown(() => t.reset(email));
    await t.recordFailure(email);
    final r = await pool.execute(
      Sql.named(
        'SELECT key_hash FROM admin_login_throttle WHERE key_hash = @k:text',
      ),
      parameters: {'k': PostgresLoginThrottle.hashKey(email)},
    );
    final stored = r.first.toColumnMap()['key_hash'] as String;
    expect(stored, hasLength(64));
    expect(stored, isNot(contains('example')));
    // …and Postgres computes the same digest, which is what makes the
    // break-glass unlock in the runbook a one-liner.
    final pg = await pool.execute(
      Sql.named("SELECT encode(sha256(@e:text::bytea), 'hex') AS h"),
      parameters: {'e': email},
    );
    expect(pg.first.toColumnMap()['h'], stored);
  });

  test('prune removes stale rows and spares fresh ones', () async {
    final old = freshKey();
    final recent = freshKey();
    final now = DateTime.utc(2026, 8, 19, 12);
    addTearDown(() => throttleAt(() => now).reset(recent));
    await throttleAt(() => DateTime.utc(2026, 8, 17, 12)).recordFailure(old);
    await throttleAt(() => now).recordFailure(recent);
    final deleted = await throttleAt(
      () => now,
    ).prune(const Duration(hours: 24));
    expect(deleted, greaterThanOrEqualTo(1));
    expect(await row(old), isNull);
    expect(await row(recent), isNotNull, reason: 'a fresh count must survive');
  });

  group('adminThrottleKey', () {
    test('trims and lower-cases, so one address is one budget', () {
      expect(adminThrottleKey('  Admin@Myweli.CI '), 'admin@myweli.ci');
      expect(adminThrottleKey('admin@myweli.ci'), 'admin@myweli.ci');
    });
  });
}
