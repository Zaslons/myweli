@Tags(['postgres'])
library;

import 'dart:async';
import 'dart:io';

import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// The behavioural half of the migration-timeout guard
/// (docs/design/backend-migration-timeouts.md). The structural half is in
/// `migration_timeouts_test.dart` and needs no database.
///
/// Everything here was first measured by hand against PostgreSQL 16 before the
/// design was written, because the answers decided its shape — in particular
/// that BOTH timeouts abort a waiting `pg_advisory_lock()`, which is why the
/// advisory lock deliberately does not get them. These tests keep the answers
/// true rather than remembered.
///
/// Gated on `DATABASE_URL` and tagged `postgres`, the same shape as
/// `migration_concurrency_test.dart`.
void main() {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    group(
      'migration timeouts (skipped — set DATABASE_URL to run)',
      () => test('needs a database', () {}),
      skip: 'requires DATABASE_URL',
    );
    return;
  }

  late Pool<void> pool;
  late String ownDbName;
  late String ownUrl;

  // Its own database, for the reason `migration_concurrency_test.dart` records:
  // `dart test` runs files concurrently, and this suite deliberately takes a
  // conflicting table lock. Doing that on the shared database would block a
  // sibling suite mid-migration.
  setUp(() async {
    final admin = createPool(url);
    ownDbName = 'myweli_to_${DateTime.now().microsecondsSinceEpoch}';
    await admin.execute('CREATE DATABASE $ownDbName');
    await admin.close();
    ownUrl = _withDatabase(url, ownDbName);
    pool = createPool(ownUrl);
  });

  tearDown(() async {
    await pool.close();
    final admin = createPool(url);
    await admin.execute('DROP DATABASE IF EXISTS $ownDbName WITH (FORCE)');
    await admin.close();
  });

  /// The setting in **milliseconds**, read from `pg_settings` rather than
  /// `SHOW`.
  ///
  /// `SHOW` echoes Postgres's own normalisation — `3000ms` comes back as `3s`
  /// and `60000ms` as `1min` — so asserting on that string means reimplementing
  /// which unit Postgres picks, and the first draft of this file got exactly
  /// that wrong. `pg_settings.setting` is always the raw value in the `unit`
  /// column's terms, which for both of these is `ms`.
  Future<int> timeoutMs(Session s, String setting) async {
    final r = await s.execute(
      "SELECT setting::bigint FROM pg_settings WHERE name = '$setting'",
    );
    return r.first.first! as int;
  }

  test('the timeouts are in force inside the transaction', () async {
    await pool.runTx((tx) async {
      await applySchemaTimeouts(tx);
      expect(
        await timeoutMs(tx, 'lock_timeout'),
        kSchemaLockTimeout.inMilliseconds,
        reason: 'the lock timeout is not actually applied',
      );
      expect(
        await timeoutMs(tx, 'statement_timeout'),
        kSchemaStatementTimeout.inMilliseconds,
      );
    });
  });

  test('and they do NOT survive the commit', () async {
    // **The one that protects request handling.** This pool also serves the
    // application: `dependencies.dart` builds one pool and hands it to both the
    // migration path and every repository. A plain `SET` would ride the pooled
    // connection into request queries and give them a 60s statement timeout
    // they never asked for. `SET LOCAL` is transaction-scoped — asserted here
    // rather than trusted, because the leak would be invisible until a slow
    // production query died at exactly 60s.
    await pool.runTx((tx) async {
      await applySchemaTimeouts(tx);
    });

    // Several times: the pool round-robins, so one clean read could simply be a
    // different connection than the one the transaction used.
    for (var i = 0; i < 6; i++) {
      expect(
        await timeoutMs(pool, 'lock_timeout'),
        0,
        reason: 'lock_timeout leaked to a pooled connection (read $i)',
      );
      expect(
        await timeoutMs(pool, 'statement_timeout'),
        0,
        reason: 'statement_timeout leaked to a pooled connection (read $i)',
      );
    }

    await pool.runTx((tx) async {
      expect(await timeoutMs(tx, 'lock_timeout'), 0);
    });
  });

  test('a lock-blocked statement FAILS instead of waiting', () async {
    // The hazard the whole change exists for. A migration needs ACCESS
    // EXCLUSIVE; something else holds a conflicting lock; unguarded, the ALTER
    // waits forever AND queues every subsequent reader of that table behind it,
    // because a pending ACCESS EXCLUSIVE request does not let new ACCESS SHARE
    // requests past. One blocked migration freezes a table that was serving
    // fine a second earlier.
    await pool.execute('CREATE TABLE blocked_probe(id int)');

    final blocker = createPool(ownUrl);
    final holding = Completer<void>();
    final release = Completer<void>();
    // A second session holds a conflicting lock for the duration.
    final held = blocker.runTx((tx) async {
      await tx.execute('LOCK TABLE blocked_probe IN ACCESS EXCLUSIVE MODE');
      holding.complete();
      await release.future;
    });
    await holding.future;

    final started = DateTime.now();
    Object? thrown;
    try {
      await pool
          .runTx((tx) async {
            await applySchemaTimeouts(tx);
            await tx.execute('ALTER TABLE blocked_probe ADD COLUMN c int');
          })
          // Not the assertion — the safety net. Without the guard this hangs
          // forever, and a hanging test is a red suite nobody can read.
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      thrown = e;
    }
    final elapsed = DateTime.now().difference(started);

    release.complete();
    await held;
    await blocker.close();

    expect(
      thrown,
      isNot(isA<TimeoutException>()),
      reason:
          'the blocked ALTER never returned — lock_timeout is not in force, '
          'and in production this would freeze every reader of that table',
    );
    expect(
      thrown.toString(),
      contains('lock timeout'),
      reason: 'it failed, but not for the reason the guard exists: $thrown',
    );
    expect(
      elapsed,
      lessThan(kSchemaLockTimeout * 4),
      reason:
          'it failed after ${elapsed.inSeconds}s, far beyond the '
          '${kSchemaLockTimeout.inSeconds}s budget',
    );
  });

  test("a migration can raise its own ceiling, and only its own", () async {
    // docs/design/backend-migration-timeouts.md §3.3. The defaults are applied
    // FIRST and the migration's statements run after, in the same transaction,
    // so a legitimately slow migration overrides the 60s default by making that
    // its first statement. Pinned because it is the documented escape hatch: if
    // ordering ever flipped, the override would be silently overwritten by the
    // default and a big backfill would die at 60s with the docs saying it
    // should not.
    await pool.runTx((tx) async {
      await applySchemaTimeouts(tx);
      await tx.execute("SET LOCAL statement_timeout = '10min'");
      expect(
        await timeoutMs(tx, 'statement_timeout'),
        const Duration(minutes: 10).inMilliseconds,
        reason: "a migration's own SET LOCAL did not take effect",
      );
      // The lock timeout is untouched by the override.
      expect(
        await timeoutMs(tx, 'lock_timeout'),
        kSchemaLockTimeout.inMilliseconds,
      );
    });

    // And the override is as transaction-scoped as the default it replaced.
    expect(await timeoutMs(pool, 'statement_timeout'), 0);
  });

  test('the real migration path runs with the guard in place', () async {
    // End to end rather than on a synthetic transaction: the whole boot
    // sequence against a pristine database, proving the timeouts do not break
    // any of the 31 migrations or the backfills — a `SET LOCAL` in the wrong
    // place would surface as a migration failing, not as a subtle drift.
    await withSchemaLock(pool, () async {
      await runMigrations(pool);
      await backfillCatalogueIfNeeded(pool);
      await seedLocalitiesIfEmpty(pool);
      await backfillSalonMarketIfNeeded(pool);
    });

    final applied = await pool.execute(
      'SELECT count(*) AS n FROM schema_migrations',
    );
    expect(
      applied.first.toColumnMap()['n'] as int,
      greaterThanOrEqualTo(31),
      reason: 'the migration path did not complete under the new timeouts',
    );
    // And it left nothing behind on the pool.
    expect(await timeoutMs(pool, 'statement_timeout'), 0);
  });
}

/// Swap the database name in a Postgres URL, keeping host/credentials/query.
String _withDatabase(String url, String db) {
  final u = Uri.parse(url);
  return u.replace(path: '/$db').toString();
}
