import 'package:myweli_backend/src/boot_config.dart';
import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// The demo-salon seed is dev-only (docs/design/infra-staging.md §1.2).
///
/// **Why this needs a test at all.** `seedProvidersIfEmpty` asked exactly one
/// question — is the `providers` table empty? — and nothing else. So the
/// sequence docs/LAUNCH.md §4 requires (purge the fictional salons from
/// production, then deploy) simply re-created them, as would any cold start
/// once `minScale` recycled an instance. Production has been serving « Barber
/// King », « Beauté Divine » and friends, with invented ratings and review
/// counts, and no gate anywhere could see it.
///
/// The composition root now gates the call on `ENV == dev`, and the function
/// re-checks. This pins the second check, because the first is a single line in
/// a composition root that a refactor can quietly drop.
///
/// No database is needed: `createPool` is lazy, so a pool pointing at an
/// unreachable host never connects. That is itself the assertion — the guard
/// must fire **before** any query, which is what makes it safe to call against
/// a production pool.
void main() {
  Pool<void> pool() => createPool('postgres://u:p@127.0.0.1:1/nonexistent');

  group('seedProvidersIfEmpty refuses outside dev', () {
    test('production is refused, and refused before touching the database', () {
      expect(
        () => seedProvidersIfEmpty(pool(), env: Env.prod),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('dev-only'), contains('prod')),
          ),
        ),
        reason: 'a connection error here would mean the guard runs too late',
      );
    });

    test(
      'staging is refused too — it seeds deliberately, with its own ids',
      () {
        // Staging is not a lesser production: it gets purpose-seeded data with
        // `stg_`-namespaced ids. These rows carry FIXED ids, so sharing them
        // across environments makes every later log line ambiguous about which
        // database produced it (docs/design/infra-staging.md §2.1).
        expect(
          () => seedProvidersIfEmpty(pool(), env: Env.staging),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('the error names the environment it was called with', () {
      // An operator reading a crash-looping boot log needs to know which value
      // of ENV produced it, not merely that something was wrong.
      expect(
        () => seedProvidersIfEmpty(pool(), env: Env.staging),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('staging'),
          ),
        ),
      );
    });
  });
}
