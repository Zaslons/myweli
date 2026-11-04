import 'dart:io';

import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// B9.12 — `provider_otp_codes` is gone (docs/design/hygiene-batch9.md §2.11).
///
/// B8.5 (#685) stopped every read and write of the Pro phone codes, but kept
/// the table: the image before it (`myweli-api-00045-8hs`) deleted from it on
/// each Pro account deletion, and dropping it in the same deploy would have
/// made a rollback turn every deletion into a 500. Production has served
/// `eca4db6` since 2026-10-22, which never names the table; migration `0043`
/// drops it, declared `rollback-unsafe` for the one rollback that would break.
void main() {
  const table = 'provider_otp_codes';
  final root = Directory.current.path.endsWith('backend')
      ? Directory.current.path
      : '${Directory.current.path}/backend';
  const migrationsFile = 'lib/src/db/migrations.dart';

  group('the source', () {
    test('no server code names the table outside the migration list', () {
      final named = <String>[
        for (final dir in ['lib', 'routes', 'bin'])
          if (Directory('$root/$dir').existsSync())
            for (final f in Directory(
              '$root/$dir',
            ).listSync(recursive: true).whereType<File>())
              if (f.path.endsWith('.dart') &&
                  !f.path.endsWith(migrationsFile) &&
                  f.readAsStringSync().contains(table))
                f.path.substring(root.length + 1),
      ];
      expect(named, isEmpty, reason: 'the table is dropped by 0043');
    });

    test('the last migration naming it drops it, and says so', () {
      final source = File('$root/$migrationsFile').readAsStringSync();
      final start = source.indexOf('const List<_Migration> _migrations = [');
      final end = source.indexOf('\n];', start);
      expect(start, isNonNegative, reason: 'the migration list was found');
      final body = source.substring(start, end);
      final ids = RegExp("id: '([0-9A-Za-z_]+)'").allMatches(body).toList();
      final naming = [
        for (var i = 0; i < ids.length; i++)
          if (body
              .substring(
                ids[i].start,
                i + 1 < ids.length ? ids[i + 1].start : body.length,
              )
              .contains(table))
            (
              id: ids[i].group(1)!,
              text: body.substring(
                ids[i].start,
                i + 1 < ids.length ? ids[i + 1].start : body.length,
              ),
            ),
      ];
      // 0003 creates it; the drop must come after, and be the last word.
      expect(naming.map((m) => m.id), [
        '0003_provider_accounts',
        '0043_drop_provider_otp_codes',
      ]);
      final drop = naming.last.text;
      expect(drop, contains('DROP TABLE IF EXISTS $table'));
      expect(
        drop.indexOf('// rollback-unsafe:'),
        greaterThan(drop.indexOf('id:')),
        reason: 'declared on the migration itself, after its id',
      );
      expect(
        drop,
        contains('00045-8hs'),
        reason: 'the declaration names the rollback that breaks',
      );
    });
  });

  group('against Postgres', () {
    final url = Platform.environment['DATABASE_URL'];
    if (url == null || url.isEmpty) {
      test(
        'the drop (skipped — set DATABASE_URL to run)',
        () {},
        skip: 'requires DATABASE_URL',
      );
      return;
    }

    late Pool<void> pool;
    setUpAll(() async {
      pool = createPool(url);
      await withSchemaLock(pool, () => runMigrations(pool));
    });
    tearDownAll(() async => pool.close());

    Future<bool> exists() async {
      final rows = await pool.execute(
        Sql.named("SELECT to_regclass('public.$table') IS NOT NULL AS ok"),
      );
      return rows.first.toColumnMap()['ok'] as bool;
    }

    test('after the migrations, the table is gone and 0043 recorded', () async {
      expect(await exists(), isFalse);
      final rows = await pool.execute(
        Sql.named('SELECT 1 FROM schema_migrations WHERE id = @id'),
        parameters: {'id': '0043_drop_provider_otp_codes'},
      );
      expect(rows, hasLength(1));
    });

    test('the migrations run again without it (a second boot)', () async {
      await withSchemaLock(pool, () => runMigrations(pool));
      expect(await exists(), isFalse);
    });
  });
}
