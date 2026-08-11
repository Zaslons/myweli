@Tags(['postgres'])
library;

import 'dart:io';

import 'package:myweli_backend/src/boot_config.dart';
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
  late String ownDbName;
  late String ownUrl;

  // **Its OWN database, not the shared one.** This suite needs a pristine
  // schema, and `dart test` runs files CONCURRENTLY — an earlier version did
  // `DROP SCHEMA public CASCADE` on the shared CI database and yanked the
  // schema out from under `postgres_repositories_test.dart` mid-migration
  // (`relation "outbound_messages" already exists`). That is the very race
  // this file exists to test, reproduced in the test harness.
  //
  // Note the shape difference: the sibling suite migrates an existing database
  // and never drops anything, which is why it is a good citizen and this one
  // has to be quarantined instead.
  setUp(() async {
    final admin = createPool(url);
    ownDbName = 'myweli_conc_${DateTime.now().microsecondsSinceEpoch}';
    await admin.execute('CREATE DATABASE $ownDbName');
    await admin.close();
    ownUrl = _withDatabase(url, ownDbName);
    pool = createPool(ownUrl);
  });

  tearDown(() async {
    await pool.close();
    final admin = createPool(url);
    // FORCE: the pool's sessions may not have fully drained yet.
    await admin.execute('DROP DATABASE IF EXISTS $ownDbName WITH (FORCE)');
    await admin.close();
  });

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

    await pool.close();
    final admin = createPool(url);
    await admin.execute('DROP DATABASE IF EXISTS $ownDbName WITH (FORCE)');
    await admin.execute('CREATE DATABASE $ownDbName');
    await admin.close();
    pool = createPool(ownUrl);

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
  await seedProvidersIfEmpty(pool, env: Env.dev);
  await backfillCatalogueIfNeeded(pool);
  await seedLocalitiesIfEmpty(pool);
  await backfillSalonMarketIfNeeded(pool);
});

/// Swap the database name in a Postgres URL, keeping host/credentials/query.
String _withDatabase(String url, String db) {
  final u = Uri.parse(url);
  return u.replace(path: '/$db').toString();
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
