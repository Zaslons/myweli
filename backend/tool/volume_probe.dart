// Times the migration shapes this codebase actually uses, against a table of a
// given size, on whatever hardware DATABASE_URL points at.
//
// **Why this exists.** `kSchemaStatementTimeout` is 60s
// (docs/design/backend-migration-timeouts.md) and has never been measured —
// §8 q3. infra-staging.md §3.2 assumed a production PITR restore would supply
// the volume to measure it; the restore was run on 2026-08-16 and production
// turned out to hold 5 user rows, so it answered nothing
// (docs/design/infra-dr-restore.md §4). Synthetic volume is the only way left.
//
//   dart run tool/volume_probe.dart                 # tiers 50k,100k,250k,500k
//   dart run tool/volume_probe.dart 100000 1000000  # explicit tiers
//
// Point DATABASE_URL at a THROWAWAY instance of the same tier as production
// (db-f1-micro). Not staging: this leaves hundreds of thousands of appointments
// behind, and staging runs `minScale: 0`, so every cold start would then pay to
// read them.
//
// **The numbers only transfer if the hardware does.** A laptop answers a
// different question than a shared-core db-f1-micro with 0.6 GB of RAM, and the
// second is the one production runs on.
import 'dart:io';

import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:postgres/postgres.dart';

/// The DDL shapes that appear in `migrations.dart` and whose cost grows with
/// the table. Each is created, timed, and dropped.
///
/// The two `EXCLUDE USING gist` constraints are the reason this file exists:
/// infra-staging.md §3.2 names them and the bare non-`CONCURRENT` `CREATE
/// INDEX` as the statements that "take ACCESS EXCLUSIVE and build inline".
const _shapes = <({String label, String create, String drop})>[
  (
    label: 'CREATE INDEX (plain btree)',
    create:
        'CREATE INDEX probe_btree ON appointments (provider_id, appointment_date)',
    drop: 'DROP INDEX IF EXISTS probe_btree',
  ),
  (
    label: 'CREATE UNIQUE INDEX … WHERE (partial)',
    create:
        'CREATE UNIQUE INDEX probe_partial ON appointments '
        '(provider_id, artist_id, appointment_date) '
        "WHERE status IN ('pending','confirmed') AND artist_id IS NOT NULL",
    drop: 'DROP INDEX IF EXISTS probe_partial',
  ),
  (
    // The shape migration 0026 adds. GiST over a tstzrange, built inline.
    label: 'ADD CONSTRAINT … EXCLUDE USING gist',
    create: '''
ALTER TABLE appointments ADD CONSTRAINT probe_no_overlap
  EXCLUDE USING gist (
    provider_id WITH =,
    artist_id WITH =,
    tstzrange(appointment_date, ends_at) WITH &&
  ) WHERE (status IN ('pending','confirmed') AND artist_id IS NOT NULL)''',
    drop: 'ALTER TABLE appointments DROP CONSTRAINT IF EXISTS probe_no_overlap',
  ),
  (
    // Migration 0009 does exactly this. PostgreSQL 11+ is supposed to store a
    // non-volatile default as metadata rather than rewriting the table — worth
    // confirming rather than believing, since a rewrite at this size would
    // dominate every other number here.
    label: 'ADD COLUMN NOT NULL DEFAULT now()',
    create:
        'ALTER TABLE appointments '
        'ADD COLUMN probe_col timestamptz NOT NULL DEFAULT now()',
    drop: 'ALTER TABLE appointments DROP COLUMN IF EXISTS probe_col',
  ),
];

Future<void> main(List<String> args) async {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln(
      'DATABASE_URL is required (point it at a THROWAWAY instance)',
    );
    exit(2);
  }
  final tiers = args.isEmpty
      ? const [50000, 100000, 250000, 500000]
      : args.map(int.parse).toList();

  final pool = createPool(url);

  // The real schema, from the real runner — not a hand-written approximation,
  // because row width is part of what is being measured.
  await withSchemaLock(pool, () => runMigrations(pool));

  // **No statement timeout while measuring.** The probe exists to find out
  // whether 60s is enough; inheriting a 60s ceiling would cap the answer at the
  // question. Set per-session here, never in the application path.
  await pool.execute('SET statement_timeout = 0');
  await pool.execute('SET lock_timeout = 0');

  // The real constraints would be checked on every insert, so loading 500k rows
  // through them measures the constraints rather than the load. They are the
  // thing under test, so they come off first and are re-created, timed, below.
  await pool.execute(
    'ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_artist_no_overlap',
  );
  await pool.execute('DROP INDEX IF EXISTS appointments_artist_slot_unique');

  stdout.writeln('server: ${await _one(pool, 'SHOW server_version')}');
  stdout.writeln(
    'mem   : shared_buffers=${await _one(pool, 'SHOW shared_buffers')} '
    'maintenance_work_mem=${await _one(pool, 'SHOW maintenance_work_mem')}',
  );
  stdout.writeln('');
  stdout.writeln('| rows | ${_shapes.map((s) => s.label).join(' | ')} |');
  stdout.writeln('|---|${_shapes.map((_) => '---').join('|')}|');

  for (final tier in tiers) {
    await _growTo(pool, tier);
    final cells = <String>[];
    for (final shape in _shapes) {
      await pool.execute(shape.drop);
      final sw = Stopwatch()..start();
      await pool.execute(shape.create);
      sw.stop();
      await pool.execute(shape.drop);
      cells.add(_fmt(sw.elapsed));
    }
    stdout.writeln('| ${_thousands(tier)} | ${cells.join(' | ')} |');
  }

  final size = await _one(
    pool,
    "SELECT pg_size_pretty(pg_total_relation_size('appointments'))",
  );
  stdout.writeln('\nappointments on disk: $size');
  await pool.close();
}

/// Tops the table up to [target] rows, generated **server-side** so the
/// measurement is not a measurement of the network.
///
/// Rows are laid out so no two share a (provider, artist, time range): the
/// timestamp advances one minute per row while `provider_id` cycles every 2000
/// and `artist_id` every 5, so a given pair recurs only every 2000 minutes —
/// far apart than the 30-minute duration. That matters because the partial
/// unique index and the GiST exclusion only cover `pending`/`confirmed` rows
/// with an artist: generating rows that fall OUTSIDE those predicates would
/// build empty indexes and report a reassuring, meaningless number.
Future<void> _growTo(Pool<void> pool, int target) async {
  final current = int.parse(
    await _one(pool, 'SELECT count(*) FROM appointments'),
  );
  if (current >= target) return;
  final sw = Stopwatch()..start();
  await pool.execute('''
INSERT INTO appointments
  (id, user_id, provider_id, service_ids, artist_id, appointment_date,
   ends_at, status, total_price, deposit_amount, balance_due,
   cancellation_window_hours, created_at)
SELECT
  'probe_' || i,
  'u' || (i % 50000),
  'p' || (i % 2000),
  '["service1"]'::jsonb,
  'a' || (i % 5),
  timestamptz '2030-01-01 00:00:00+00' + (i * interval '1 minute'),
  timestamptz '2030-01-01 00:00:00+00' + (i * interval '1 minute') + interval '30 minutes',
  CASE WHEN i % 4 = 0 THEN 'confirmed' ELSE 'pending' END,
  15000, 0, 15000, 24, now()
FROM generate_series($current, ${target - 1}) AS g(i)
''');
  sw.stop();
  stdout.writeln(
    '  … grew ${_thousands(current)} → ${_thousands(target)} in ${_fmt(sw.elapsed)}',
  );
}

Future<String> _one(Pool<void> pool, String sql) async =>
    (await pool.execute(sql)).first.first.toString();

String _fmt(Duration d) => d.inMilliseconds < 1000
    ? '${d.inMilliseconds} ms'
    : '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

String _thousands(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]} ',
);
