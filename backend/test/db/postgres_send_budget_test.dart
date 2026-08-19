import 'dart:io';

import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_send_budget.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// The send budget's atomicity, against a real Postgres.
///
/// **Why this was missing, and why that mattered.** `send_budget_test.dart`
/// exercises only `InMemorySendBudget`, which runs on a single-threaded event
/// loop — so it proves the INTERFACE's semantics and nothing whatsoever about
/// the SQL. Yet the SQL is the entire reason this counter went to Postgres
/// rather than memory: the implementation's own comment says a read-then-write
/// "would let two instances both read 59, both decide there is room, and both
/// send."
///
/// That claim has been live in production since 2026-08-19 (revision
/// `myweli-api-00021-p9z`) resting on a reading of the statement. A near
/// identical counter added the same day — `PostgresRateLimiter` — got a real
/// database behind its claim, and this one did not. Same shape, same assertion,
/// one of them evidenced.
///
/// Design: docs/design/backend-email-send-budget.md §10
void main() {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    test(
      'postgres send budget (skipped — set DATABASE_URL to run)',
      () {},
      skip: 'requires DATABASE_URL',
    );
    return;
  }

  late Pool<void> pool;

  setUpAll(() async {
    pool = createPool(url);
    // Under the schema lock, as `dependencies.dart` does. `runMigrations` does
    // not take it itself, and calling it bare races every other DB-gated file
    // with 23505 on `pg_type_typname_nsp_index` — `CREATE TABLE IF NOT EXISTS`
    // is not atomic against a concurrent creator.
    await withSchemaLock(pool, () => runMigrations(pool));
  });

  tearDownAll(() async => pool.close());

  /// **The buckets are fixed** — `cold` and `warm`, one row per hour each — so
  /// unlike the rate limiter there is no fresh key to hide behind. Clear them
  /// before and after instead, which is also what makes the suite re-runnable
  /// against the same database without a reset.
  Future<void> clear() => pool.execute(
    "DELETE FROM email_send_budget WHERE bucket IN ('cold', 'warm')",
  );

  setUp(clear);
  tearDown(clear);

  test('the table exists and migration 0033 applied', () async {
    final rows = await pool.execute(
      Sql.named(
        "SELECT to_regclass('public.email_send_budget') IS NOT NULL AS ok",
      ),
    );
    expect(rows.first.toColumnMap()['ok'], isTrue);
  });

  test('it counts, and refuses past the ceiling', () async {
    final b = PostgresSendBudget(pool, ceilings: (cold: 3, warm: 100));
    for (var i = 1; i <= 3; i++) {
      final r = await b.reserve(EmailClass.cold);
      expect(r.ok, isTrue, reason: 'reservation $i of 3');
      expect(r.sent, i, reason: 'the post-increment value is returned');
      expect(r.ceiling, 3);
    }
    final over = await b.reserve(EmailClass.cold);
    expect(over.ok, isFalse);
    expect(over.sent, 4);
    expect(await b.used(EmailClass.cold), 4);
  });

  test('CONCURRENT reservations get distinct values — the whole claim', () async {
    // 25 statements in flight against a ceiling of 10. Under a read-then-write
    // several callers would read the same value and more than ten would be
    // allowed to send. Distinctness is asserted as well as the count, because a
    // count of ten could in principle arrive from a different mistake.
    final b = PostgresSendBudget(pool, ceilings: (cold: 10, warm: 10));
    final results = await Future.wait([
      for (var i = 0; i < 25; i++) b.reserve(EmailClass.cold),
    ]);
    expect(results.where((r) => r.ok), hasLength(10));
    expect(
      results.map((r) => r.sent).toSet(),
      hasLength(25),
      reason: 'every caller saw a DIFFERENT post-increment value',
    );
    expect(await b.used(EmailClass.cold), 25);
  });

  test('EXHAUSTING COLD DOES NOT TOUCH WARM, in the database too', () async {
    // The property the two-class design exists for, asserted where it actually
    // lives — a single shared row would make a cold flood drop every booking
    // confirmation, which is the availability attack the design refuses to
    // build. The in-memory test asserts the same thing about a Map; this
    // asserts it about the primary key.
    final b = PostgresSendBudget(pool, ceilings: (cold: 2, warm: 5));
    for (var i = 0; i < 4; i++) {
      await b.reserve(EmailClass.cold);
    }
    expect(
      (await b.reserve(EmailClass.cold)).ok,
      isFalse,
      reason: 'cold spent',
    );
    expect(
      (await b.reserve(EmailClass.warm)).ok,
      isTrue,
      reason: 'a real customer still gets their confirmation',
    );
    expect(await b.used(EmailClass.warm), 1);
  });

  test('the two classes really are two rows', () async {
    final b = PostgresSendBudget(pool, ceilings: (cold: 5, warm: 5));
    await b.reserve(EmailClass.cold);
    await b.reserve(EmailClass.warm);
    final rows = await pool.execute(
      "SELECT bucket, sent FROM email_send_budget "
      "WHERE bucket IN ('cold', 'warm') ORDER BY bucket",
    );
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.toColumnMap()['bucket']), ['cold', 'warm']);
    expect(rows.map((r) => r.toColumnMap()['sent']), [1, 1]);
  });

  test('an unused class reports 0 rather than throwing', () async {
    final b = PostgresSendBudget(pool);
    expect(await b.used(EmailClass.warm), 0);
  });

  test('the window is truncated to the hour', () async {
    final b = PostgresSendBudget(pool);
    await b.reserve(EmailClass.cold);
    final rows = await pool.execute(
      "SELECT window_start FROM email_send_budget WHERE bucket = 'cold'",
    );
    final w = rows.first.toColumnMap()['window_start'] as DateTime;
    expect(w.minute, 0);
    expect(w.second, 0);
    expect(
      w.isUtc || w.toUtc() == w,
      isTrue,
      reason: 'the window is UTC, so instances in any zone agree',
    );
  });
}
