import 'dart:io';

import 'package:test/test.dart';

/// Rolling the backend image back must not strand it on a schema it cannot
/// read (docs/design/infra-rollback.md §5.2).
///
/// **Why this is checkable at all.** `runMigrations` iterates its OWN compiled
/// list and asks `SELECT 1 FROM schema_migrations WHERE id = @id` per entry, so
/// rows for migrations an older image has never heard of are simply not
/// consulted. The boot path is therefore safe by construction, and the only
/// remaining question is whether the older CODE can run against the newer
/// SCHEMA. That is a property of the DDL, and it is decided in this file.
///
/// **What is safe.** Additive statements — `ADD COLUMN`, `CREATE TABLE`,
/// `CREATE INDEX`, and also `DROP NOT NULL` or dropping a `UNIQUE` constraint,
/// which WIDEN what the schema accepts. Old code ignores what it does not
/// select. All 31 migrations are of this kind today.
///
/// **What is not.** `DROP COLUMN`, `DROP TABLE`, `RENAME`, `SET NOT NULL`, a
/// narrowing type change: old code selects a column that is gone, or inserts a
/// row that now violates a constraint. There are **no down statements** —
/// `migrations.dart` is a list of forward-only `(id, statements)` records — so
/// there is nothing to run in the other direction.
///
/// **This is deliberately not a ban.** `DROP COLUMN` is the legitimate
/// *contract* step of expand → migrate → contract, once no deployed code reads
/// the column ([LAUNCH.md](../../../docs/LAUNCH.md) §1.4 requires that sequence
/// anyway, because installed app versions cannot be rolled back either). The
/// test asks only that it be DECLARED, with a `// rollback-unsafe:` comment
/// naming why — which turns an invisible property of the schema into a line in
/// a diff, and gives whoever is holding the runbook at 2am a greppable answer
/// to "can I roll back past this one?".
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  final source = File(
    '$root/backend/lib/src/db/migrations.dart',
  ).readAsStringSync();

  /// The comment a migration carries to declare it knows what it is doing.
  const declaration = '// rollback-unsafe:';

  /// DDL that leaves an older image unable to run.
  ///
  /// Every pattern here is narrow on purpose, because the near misses in this
  /// file are all SAFE and flagging them would train everyone to add the
  /// declaration comment reflexively:
  ///
  ///   · `ALTER COLUMN phone_number DROP NOT NULL` widens — and must not be
  ///     caught by the `SET NOT NULL` or the type-change pattern;
  ///   · `DROP CONSTRAINT IF EXISTS users_phone_number_key` widens — dropping a
  ///     UNIQUE, CHECK or FK constraint only ever accepts more rows;
  ///   · `business_type text NOT NULL` and `target_type text NOT NULL` are
  ///     column definitions that contain the word "type", which is why the
  ///     type-change pattern requires the literal `ALTER COLUMN … TYPE` shape
  ///     rather than looking for `TYPE`.
  final destructive = <String, RegExp>{
    'DROP COLUMN': RegExp(r'\bDROP\s+COLUMN\b', caseSensitive: false),
    'DROP TABLE': RegExp(r'\bDROP\s+TABLE\b', caseSensitive: false),
    'DROP VIEW': RegExp(r'\bDROP\s+VIEW\b', caseSensitive: false),
    'DROP TYPE': RegExp(r'\bDROP\s+TYPE\b', caseSensitive: false),
    'RENAME': RegExp(r'\bRENAME\b', caseSensitive: false),
    'SET NOT NULL': RegExp(r'\bSET\s+NOT\s+NULL\b', caseSensitive: false),
    'a narrowing type change': RegExp(
      r'\bALTER\s+COLUMN\s+\w+\s+(SET\s+DATA\s+)?TYPE\b',
      caseSensitive: false,
    ),
    'TRUNCATE': RegExp(r'\bTRUNCATE\b', caseSensitive: false),
  };

  // ---- slice the list into one chunk per migration --------------------------
  // Per-migration rather than whole-file, so the declaration comment has to sit
  // on the migration that needs it. A file-wide search would let one legitimate
  // `// rollback-unsafe:` from 2026 bless every destructive statement written
  // afterwards.
  final listStart = source.indexOf('const List<_Migration> _migrations = [');
  final listEnd = source.indexOf('\n];', listStart);
  final body = listStart < 0 || listEnd < 0
      ? ''
      : source.substring(listStart, listEnd);
  final ids = RegExp("id: '([0-9A-Za-z_]+)'").allMatches(body).toList();

  ({String id, String text}) chunk(int i) => (
    id: ids[i].group(1)!,
    text: body.substring(
      ids[i].start,
      i + 1 < ids.length ? ids[i + 1].start : body.length,
    ),
  );

  group('the migration list is actually being read', () {
    // **The check that keeps the rest of this file from passing vacuously.**
    // Every assertion below is a loop over `ids`. If the anchor strings above
    // are ever edited in `migrations.dart` — a renamed constant, a reformatted
    // literal — `ids` becomes empty, every loop runs zero times, and this file
    // goes green while checking nothing at all. That is the failure this
    // repository keeps finding, so it is asserted rather than hoped for.
    test('the list was located and parsed', () {
      expect(
        listStart,
        isNonNegative,
        reason:
            'could not find `const List<_Migration> _migrations = [` in '
            'migrations.dart — the anchor this test slices on has been renamed',
      );
      expect(listEnd, greaterThan(listStart));
    });

    test('it found a plausible number of migrations', () {
      // A floor, not the exact count: this must not need editing every time a
      // migration lands. It only has to fail if parsing collapses.
      expect(
        ids.length,
        greaterThanOrEqualTo(25),
        reason:
            'parsed ${ids.length} migrations, which is fewer than have already '
            'shipped — the `id:` pattern no longer matches the source',
      );
    });

    test('the ids are unique and ordered', () {
      final names = [for (var i = 0; i < ids.length; i++) chunk(i).id];
      expect(
        names.toSet().length,
        names.length,
        reason:
            'a duplicate migration id means one of them is recorded in '
            'schema_migrations under the other name and silently never runs',
      );
      expect(
        names,
        orderedEquals([...names]..sort()),
        reason:
            'migrations are applied in list order and named with a numeric '
            'prefix; a list that is not sorted means the two disagree',
      );
    });
  });

  group('no migration strands an older image', () {
    for (var i = 0; i < ids.length; i++) {
      final m = chunk(i);
      test(m.id, () {
        final declared = m.text.contains(declaration);
        for (final entry in destructive.entries) {
          if (!entry.value.hasMatch(m.text)) continue;
          expect(
            declared,
            isTrue,
            reason:
                'migration ${m.id} contains ${entry.key}, which an image '
                'deployed before it cannot run against — and there are no down '
                'statements to undo it.\n\n'
                'If that is intended (the CONTRACT step of expand → migrate → '
                'contract, with no deployed code still reading it), say so on '
                'the migration:\n\n'
                '    $declaration <why this is safe to land now>\n\n'
                'See docs/design/infra-rollback.md §5.2.',
          );
        }
      });
    }
  });

  group('the guard can fire', () {
    // Without this, every pattern above could be quietly wrong — a typo, an
    // anchor that never matches real DDL — and the suite would stay green
    // forever precisely BECAUSE no migration is destructive. A guard that
    // cannot match is worth less than no guard, because it is believed.
    const samples = {
      'DROP COLUMN': 'ALTER TABLE users DROP COLUMN avatar_url',
      'DROP TABLE': 'DROP TABLE IF EXISTS otp_codes',
      'DROP VIEW': 'DROP VIEW provider_summary',
      'DROP TYPE': 'DROP TYPE booking_status',
      'RENAME': 'ALTER TABLE users RENAME COLUMN name TO full_name',
      'SET NOT NULL': 'ALTER TABLE users ALTER COLUMN email SET NOT NULL',
      'a narrowing type change':
          'ALTER TABLE appointments ALTER COLUMN total_price TYPE int',
      'TRUNCATE': 'TRUNCATE TABLE appointments',
    };

    test('every pattern matches the statement it is named for', () {
      expect(
        samples.keys.toSet(),
        destructive.keys.toSet(),
        reason: 'a pattern was added or renamed without a sample to prove it',
      );
      samples.forEach((name, sql) {
        expect(
          destructive[name]!.hasMatch(sql),
          isTrue,
          reason: '`$name` does not match `$sql` — the pattern cannot fire',
        );
      });
    });

    test('the widening statements already in the file are NOT flagged', () {
      // The other half of "can fire": a guard that matches everything gets
      // switched off. These three are real lines from migrations.dart, and all
      // three widen the schema, so an older image runs against them fine.
      const safe = [
        'ALTER TABLE users ALTER COLUMN phone_number DROP NOT NULL',
        'ALTER TABLE users DROP CONSTRAINT IF EXISTS users_phone_number_key',
        'CREATE TABLE IF NOT EXISTS provider_users (business_type text NOT NULL)',
      ];
      for (final sql in safe) {
        for (final entry in destructive.entries) {
          expect(
            entry.value.hasMatch(sql),
            isFalse,
            reason:
                '`${entry.key}` falsely flags the widening statement `$sql`',
          );
        }
      }
    });

    test('the sample DDL would be caught in a real migration', () {
      // End to end, on the shape the loop above actually sees: a migration
      // chunk with a destructive statement and no declaration must trip at
      // least one pattern, and adding the comment must clear it.
      const undeclared = """
  (
    id: '9999_drop_it',
    statements: ['ALTER TABLE users DROP COLUMN avatar_url'],
  ),""";
      expect(destructive.values.any((p) => p.hasMatch(undeclared)), isTrue);
      expect(undeclared.contains(declaration), isFalse);
      expect(
        '$undeclared\n    $declaration nothing reads it since v1.2'.contains(
          declaration,
        ),
        isTrue,
      );
    });
  });
}
