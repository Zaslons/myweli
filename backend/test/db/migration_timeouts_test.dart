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
    //
    // **Enumerated LOOSELY, and that is the whole point.** The first version of
    // this scan matched `runTx\(\(tx\) async \{` — today's exact spelling — and
    // paired it with a `>= 4` floor. That combination can only detect the
    // pattern breaking DOWNWARD: a *new* transaction written any other way is
    // not matched, the count stays at four, the floor still passes, and the
    // unguarded transaction is never inspected. It was demonstrated by
    // appending a backfill spelled `pool.runTx((TxSession tx) async {` — format
    // clean, analyzer clean, whole suite green.
    //
    // That spelling is not hypothetical: `postgres_providers_repository.dart`
    // already writes `_pool.runTx<List<String>?>((tx) async {` at six sites, so
    // a value-returning schema-setup transaction would *naturally* be written
    // in a form the strict pattern misses.
    //
    // So: match any `runTx` that is called at all, and check every one.
    final calls = RegExp(r'\brunTx\s*[<(]').allMatches(source).toList();

    /// The first real statement after [from], skipping blank lines and both
    /// comment forms — with **no byte window**.
    ///
    /// The first version truncated at 240 characters after the brace, so a
    /// transaction whose opening comment was longer than that had its whole
    /// window skipped, returned `''`, and failed with a message asserting the
    /// call was missing while it sat 300 characters away. A guard whose failure
    /// text is false is worse than none: the cheapest way to make the suite
    /// green again is to delete the comment, or the test.
    String firstStatementAfter(int from) {
      var inBlock = false;
      for (final raw in source.substring(from).split('\n')) {
        var t = raw.trim();
        while (t.isNotEmpty) {
          if (inBlock) {
            final close = t.indexOf('*/');
            if (close < 0) {
              t = '';
              break;
            }
            t = t.substring(close + 2).trim();
            inBlock = false;
            continue;
          }
          if (t.startsWith('/*')) {
            inBlock = true;
            t = t.substring(2);
            continue;
          }
          if (t.startsWith('//')) t = '';
          break;
        }
        if (t.isNotEmpty) return t;
      }
      return '';
    }

    test('the scan found the transactions it is supposed to check', () {
      // Anti-vacuity, and now it is the ONLY thing the floor has to do: every
      // call the regex finds is inspected below, so the floor no longer has to
      // notice a new one — it only has to notice the scan collapsing to zero.
      expect(
        calls.length,
        greaterThanOrEqualTo(4),
        reason:
            'found ${calls.length} `runTx` calls in migrations.dart; there are '
            'at least four (runMigrations, the catalogue backfill, the '
            'locality seed, the salon-market backfill). The pattern no longer '
            'matches the source.',
      );
    });

    test('each one applies the timeouts first', () {
      for (final m in calls) {
        // FIRST statement, because a migration's own `SET LOCAL` is meant to
        // override the default (§3.3) and cannot if the default lands after it.
        final brace = source.indexOf('{', m.start);
        expect(
          brace,
          isNonNegative,
          reason: 'a `runTx` call at offset ${m.start} opens no closure body',
        );
        final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        expect(
          firstStatementAfter(brace + 1),
          contains('applySchemaTimeouts(tx)'),
          reason:
              'the transaction opened at migrations.dart:$line does not begin '
              'with `await applySchemaTimeouts(tx);` — it runs unbounded, so a '
              'lock-blocked statement inside it waits forever and queues every '
              'reader of that table behind it.\n\nStarts with: '
              '${firstStatementAfter(brace + 1)}',
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
