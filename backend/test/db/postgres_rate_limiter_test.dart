import 'dart:io';

import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_rate_limiter.dart';
import 'package:myweli_backend/src/security/identity_limits.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// The atomicity claim, against a real Postgres.
///
/// **This is the only thing that can prove it.** The in-memory limiter runs on
/// a single-threaded event loop, so its "concurrent" test proves the interface's
/// semantics and nothing about the SQL. Whether
/// `INSERT … ON CONFLICT DO UPDATE … RETURNING` really hands each concurrent
/// caller a distinct post-increment value is a property of the database, and
/// reading the statement is not evidence.
///
/// Worth stating: `PostgresSendBudget` — shipped to production, same shape —
/// has no equivalent test, so its atomicity currently rests on reading the SQL.
/// Same gap, worth its own task.
void main() {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    test(
      'postgres rate limiter (skipped — set DATABASE_URL to run)',
      () {},
      skip: 'requires DATABASE_URL',
    );
    return;
  }

  late Pool<void> pool;
  late PostgresRateLimiter limiter;
  var seq = 0;

  setUpAll(() async {
    pool = createPool(url);
    await runMigrations(pool);
    limiter = PostgresRateLimiter(pool);
  });

  tearDownAll(() async => pool.close());

  /// A bucket nothing else uses, so the suite is re-runnable against the same
  /// database without a reset.
  String freshBucket() =>
      'test:${DateTime.now().microsecondsSinceEpoch}:${seq++}';

  Future<void> purge(String bucket) => pool.execute(
    Sql.named('DELETE FROM identity_rate_limits WHERE bucket = @b'),
    parameters: {'b': bucket},
  );

  test('the table exists and the migration applied', () async {
    final rows = await pool.execute(
      Sql.named(
        "SELECT to_regclass('public.identity_rate_limits') IS NOT NULL AS ok",
      ),
    );
    expect(rows.first.toColumnMap()['ok'], isTrue);
  });

  test('counts, and refuses past the limit', () async {
    final b = freshBucket();
    addTearDown(() => purge(b));
    for (var i = 1; i <= 3; i++) {
      final v = await limiter.hit(b, limit: 3, window: kIdentityWindow);
      expect(v.ok, isTrue);
      expect(v.hits, i, reason: 'the post-increment value is returned');
    }
    final over = await limiter.hit(b, limit: 3, window: kIdentityWindow);
    expect(over.ok, isFalse);
    expect(over.hits, 4);
    expect(await limiter.used(b, window: kIdentityWindow), 4);
  });

  test('CONCURRENT hits get distinct values — the atomicity claim', () async {
    // 25 statements in flight against a limit of 10. If the upsert were a
    // read-then-write, several would read the same value and more than 10 would
    // be allowed. Asserting on distinctness as well as the count, because a
    // count of 10 could in principle come from a different mistake.
    final b = freshBucket();
    addTearDown(() => purge(b));
    final results = await Future.wait([
      for (var i = 0; i < 25; i++)
        limiter.hit(b, limit: 10, window: kIdentityWindow),
    ]);
    expect(results.where((r) => r.ok), hasLength(10));
    expect(
      results.map((r) => r.hits).toSet(),
      hasLength(25),
      reason: 'every caller saw a DIFFERENT post-increment value',
    );
    expect(await limiter.used(b, window: kIdentityWindow), 25);
  });

  test('two buckets do not share a row', () async {
    final a = freshBucket();
    final b = freshBucket();
    addTearDown(() => purge(a));
    addTearDown(() => purge(b));
    for (var i = 0; i < 5; i++) {
      await limiter.hit(a, limit: 5, window: kIdentityWindow);
    }
    expect(
      (await limiter.hit(a, limit: 5, window: kIdentityWindow)).ok,
      isFalse,
    );
    expect(
      (await limiter.hit(b, limit: 5, window: kIdentityWindow)).ok,
      isTrue,
    );
  });

  test('an unused bucket reports 0 rather than throwing', () async {
    expect(await limiter.used(freshBucket(), window: kIdentityWindow), 0);
  });
}
