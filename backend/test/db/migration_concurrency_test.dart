@Tags(['postgres'])
library;

import 'dart:io';

import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// Schema setup must survive two processes booting at once (G1).
///
/// Render ran **one always-on instance**, so `initializeDatabase()` was a
/// sequence that never had a competitor. Cloud Run starts cold instances in
/// parallel, and every step it runs is a migration or a **check-then-act** seed
/// — `SELECT count(*)` → `if > 0 return` → `INSERT`. Two instances both read
/// zero and both insert.
///
/// The failure modes differ, and the quiet one is the dangerous one:
///
///   · `seedProvidersIfEmpty` inserts FIXED ids → primary-key conflict → the
///     loser crash-loops on boot. An outage, but loud.
///   · `backfillCatalogueIfNeeded` generates FRESH ids → nothing collides → it
///     silently DOUBLES every salon's service list.
///
/// Gated on `DATABASE_URL` and tagged `postgres`, the same shape as
/// `postgres_repositories_test.dart`.
void main() {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    group(
      'schema-setup concurrency (skipped — set DATABASE_URL to run)',
      () => test('needs a database', () {}),
      skip: 'requires DATABASE_URL',
    );
    return;
  }

  late Pool<void> pool;

  setUp(() async {
    pool = createPool(url);
    // A pristine schema per test: the race only exists on a database that has
    // not been seeded yet, which is exactly a fresh Cloud Run environment.
    await pool.execute('DROP SCHEMA public CASCADE');
    await pool.execute('CREATE SCHEMA public');
  });

  tearDown(() async => pool.close());

  test('concurrency does not change the outcome', () async {
    // The honest invariant: run the boot sequence ONCE on a pristine schema
    // and record what it produces, then run it TWICE CONCURRENTLY on another
    // pristine schema and demand the same numbers.
    //
    // An earlier draft asserted that provider_services was a whole multiple of
    // providers. That was invented rather than derived, and it is false — the
    // seed gives 4 providers 5 services between them. Measuring the sequential
    // result instead means the test cannot be wrong about what "correct" is.
    await _setup(pool);
    final expected = await _snapshot(pool);

    await _freshSchema(pool);
    await Future.wait([_setup(pool), _setup(pool)]);
    final actual = await _snapshot(pool);

    expect(
      expected['providers'],
      greaterThan(0),
      reason:
          'the seed must actually run — equal counts over an EMPTY database '
          'would pass for the wrong reason',
    );
    expect(
      actual,
      expected,
      reason:
          'two concurrent boots produced different data than one boot: '
          'the check-then-act seeds raced',
    );
  });

  test(
    'a third setup over an already-seeded database changes nothing',
    () async {
      await _setup(pool);
      final before = await _count(pool, 'providers');
      final servicesBefore = await _count(pool, 'provider_services');

      await _setup(pool);

      // The pair for the test above: it proves the guard is idempotence, not
      // merely mutual exclusion. A lock that serialised two runs but let the
      // second one re-seed would pass the first test and fail this one.
      expect(await _count(pool, 'providers'), before);
      expect(await _count(pool, 'provider_services'), servicesBefore);
    },
  );
}

/// The production boot sequence, minus the parts that need the composition
/// root. Mirrors `initializeDatabase()`'s locked block.
Future<void> _setup(Pool<void> pool) => withSchemaLock(pool, () async {
  await runMigrations(pool);
  await seedProvidersIfEmpty(pool);
  await backfillCatalogueIfNeeded(pool);
  await seedLocalitiesIfEmpty(pool);
  await backfillSalonMarketIfNeeded(pool);
});

Future<void> _freshSchema(Pool<void> pool) async {
  await pool.execute('DROP SCHEMA public CASCADE');
  await pool.execute('CREATE SCHEMA public');
}

/// Every table the locked block writes to. Comparing the whole map rather than
/// one count means a race in ANY of the five steps shows up.
Future<Map<String, int>> _snapshot(Pool<void> pool) async => {
  for (final t in const [
    'providers',
    'provider_services',
    'provider_working_hours',
    'countries',
    'cities',
    'areas',
  ])
    t: await _count(pool, t),
};

Future<int> _count(Pool<void> pool, String table) async {
  final r = await pool.execute('SELECT count(*) AS n FROM $table');
  return r.first.toColumnMap()['n'] as int;
}
