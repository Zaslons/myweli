import 'dart:io';

import 'package:myweli_backend/src/db/migrations.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The offline half of the migration-timeout guard
/// (docs/design/backend-migration-timeouts.md).
///
/// **Deliberately NOT tagged `postgres`, and in its own file.** The behavioural
/// half lives in `migration_timeouts_postgres_test.dart`, which self-skips
/// without a `DATABASE_URL` — so on a machine or a CI job with no database,
/// every assertion about this feature would vanish. These checks need no
/// database and must therefore be impossible to skip: if a `postgres` tag
/// exclusion is ever configured, the structural guard survives it.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  final source = File(
    '$root/backend/lib/src/db/migrations.dart',
  ).readAsStringSync();

  group('every schema-setup transaction is bounded', () {
    // `runMigrations` is not the only transaction on this path — the catalogue
    // backfill, the locality seed and the salon-market backfill all open one,
    // and the backfills are the statements that touch every row, so they are
    // the MOST likely to be slow or lock-blocked. A new one added later would
    // be silently unguarded, which is the shape of defect this repository keeps
    // finding: not a wrong rule, a rule that stopped covering everything.
    final openings = RegExp(
      r'runTx\(\(tx\) async \{',
    ).allMatches(source).toList();

    test('the scan found the transactions it is supposed to check', () {
      // Anti-vacuity. Every assertion below iterates `openings`; if the pattern
      // stops matching — a reformat, a renamed parameter — the loop runs zero
      // times and this file goes green while checking nothing.
      expect(
        openings.length,
        greaterThanOrEqualTo(4),
        reason:
            'found ${openings.length} `runTx((tx) async {` sites in '
            'migrations.dart; there are at least four (runMigrations, the '
            'catalogue backfill, the locality seed, the salon-market '
            'backfill). The pattern no longer matches the source.',
      );
    });

    test('each one applies the timeouts first', () {
      for (final m in openings) {
        // The next few lines only: `applySchemaTimeouts` must be the FIRST
        // statement, because a migration's own `SET LOCAL` is meant to override
        // the default (§3.3) and cannot if the default is applied afterwards.
        final head = source.substring(
          m.end,
          (m.end + 240).clamp(0, source.length),
        );
        final firstStatement = head
            .split('\n')
            .map((l) => l.trim())
            .firstWhere(
              (l) => l.isNotEmpty && !l.startsWith('//'),
              orElse: () => '',
            );
        expect(
          firstStatement,
          contains('applySchemaTimeouts(tx)'),
          reason:
              'a transaction in migrations.dart does not begin with '
              '`await applySchemaTimeouts(tx);` — it runs unbounded, so a '
              'lock-blocked statement inside it waits forever and queues every '
              'reader of that table behind it.\n\nStarts with: $firstStatement',
        );
      }
    });
  });

  group('the two budgets relate correctly', () {
    test('the lock timeout is well below the statement timeout', () {
      // PostgreSQL's own guidance: a `lock_timeout` at or above
      // `statement_timeout` can never be the reported cause, because the
      // statement timeout fires first. They are kept an order of magnitude
      // apart so that "blocked" and "slow" stay distinguishable in a deploy
      // log — which is the whole diagnostic value of setting both.
      expect(kSchemaLockTimeout, lessThan(kSchemaStatementTimeout));
      expect(
        kSchemaLockTimeout.inMilliseconds * 5,
        lessThanOrEqualTo(kSchemaStatementTimeout.inMilliseconds),
        reason:
            'the two timeouts are close enough that the statement timeout may '
            'mask the lock timeout; keep them clearly separated',
      );
    });

    test('a bounded statement still fits inside the startupProbe budget', () {
      // Read from the service files rather than restated, so shortening the
      // probe cannot silently invalidate this arithmetic. If a single statement
      // could outlast the probe, Cloud Run would kill the instance before the
      // timeout ever reported a cause — the guard would exist and never be the
      // thing you see.
      for (final name in ['service.yaml', 'service-staging.yaml']) {
        final svc =
            loadYaml(File('$root/infra/gcp/$name').readAsStringSync())
                as YamlMap;
        final app = (svc['spec']['template']['spec']['containers'] as YamlList)
            .firstWhere((c) => c['name'] == 'app');
        final probe = app['startupProbe'] as YamlMap;
        final budget = Duration(
          seconds:
              (probe['periodSeconds'] as int) *
              (probe['failureThreshold'] as int),
        );
        expect(
          kSchemaStatementTimeout,
          lessThan(budget),
          reason:
              '$name allows ${budget.inSeconds}s of startup, but one schema '
              'statement may run for ${kSchemaStatementTimeout.inSeconds}s',
        );
      }
    });
  });

  group('the advisory lock is deliberately left unbounded', () {
    // The measurement that shaped this design: BOTH timeouts abort a waiting
    // `pg_advisory_lock()`. That lock is contended BY DESIGN — when Cloud Run
    // instances cold-start together exactly one wins and the others are
    // supposed to wait — so a timeout there does not bound a pathology, it puts
    // a deadline on normal contention and kills every instance that loses the
    // race once migrations outlast it.
    //
    // This is the assertion that stops a future reader from "finishing the
    // job" by adding the timeouts to `withSchemaLock` as well.
    test('withSchemaLock sets no timeout', () {
      final start = source.indexOf('Future<void> withSchemaLock');
      expect(start, isNonNegative, reason: 'withSchemaLock has been renamed');
      final body = source.substring(start, source.length);
      final end = body.indexOf('\n}');
      final fn = body.substring(0, end < 0 ? body.length : end);

      expect(
        fn,
        isNot(contains('applySchemaTimeouts')),
        reason:
            'withSchemaLock applies the schema timeouts. Both of them abort a '
            'WAITING pg_advisory_lock (measured), and that wait is normal '
            'contention between cold-starting instances — bounding it fails '
            'healthy deploys. See docs/design/backend-migration-timeouts.md '
            '§3.1.',
      );
      for (final setting in ['lock_timeout', 'statement_timeout']) {
        expect(
          fn,
          isNot(contains(setting)),
          reason:
              'withSchemaLock sets $setting — see the reason above; the '
              'advisory-lock wait must stay unbounded',
        );
      }
    });
  });
}
