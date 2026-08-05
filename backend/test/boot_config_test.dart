import 'package:myweli_backend/src/boot_config.dart';
import 'package:test/test.dart';

/// The composition root's production guards (G1).
///
/// **These are the first tests any of them have ever had.** Before this,
/// `dependencies.dart` had five importers and not one was a test file, so every
/// prod fail-fast in it — `JWT_SECRET`, the storage block, messaging, push —
/// was real and entirely unproven.
///
/// They are testable at all only because the resolvers now take the raw value
/// as an argument. `Platform.environment` is process-wide and immutable in
/// Dart: a test cannot flip `ENV` and re-enter the composition root, and a
/// spawned isolate shares the same environment. Taking the value as a parameter
/// is the same shape `AuthMethods.parse(String?)` already uses.
void main() {
  group('DATABASE_URL — the guard that did not exist', () {
    test('production with no URL refuses to start', () {
      // The whole point. Without this the app boots on in-memory repositories
      // and serves a green API that loses every booking on restart, with
      // `/health` reporting ok throughout because it never touches the DB.
      expect(
        () => resolveDatabaseUrl(null, isProd: true),
        throwsA(isA<StateError>()),
      );
    });

    test('production with an EMPTY or whitespace URL also refuses', () {
      // A platform that injects an unset reference hands you '' or padding —
      // which the old code passed straight to createPool as a real value.
      for (final raw in ['', '   ', '\t\n']) {
        expect(
          () => resolveDatabaseUrl(raw, isProd: true),
          throwsA(isA<StateError>()),
          reason: 'a blank URL is unset, not a connection string: "$raw"',
        );
      }
    });

    test('production WITH a URL starts, and the value is trimmed', () {
      expect(
        resolveDatabaseUrl('  postgres://u:p@h:5432/db  ', isProd: true),
        'postgres://u:p@h:5432/db',
      );
    });

    test('DEV with no URL still runs in-memory — the pair', () {
      // Without this, "always throw" would satisfy every assertion above and
      // break every local run and the whole unit suite, which has no database.
      expect(resolveDatabaseUrl(null, isProd: false), isNull);
      expect(resolveDatabaseUrl('', isProd: false), isNull);
    });
  });

  group('JWT_SECRET', () {
    test('production with no secret refuses to start', () {
      expect(
        () => resolveJwtSecret(null, isProd: true),
        throwsA(isA<StateError>()),
      );
    });

    test('dev falls back, and the fallback is never a real secret', () {
      final s = resolveJwtSecret(null, isProd: false);
      expect(s, isNotEmpty);
      expect(
        s,
        contains('dev'),
        reason: 'the dev fallback must be self-evidently not a production key',
      );
    });

    test('a supplied secret wins in both modes', () {
      expect(resolveJwtSecret(' k ', isProd: true), 'k');
      expect(resolveJwtSecret(' k ', isProd: false), 'k');
    });
  });

  group('assertProductionBootConfig — why the guards fire at BOOT', () {
    test('it throws for a missing DATABASE_URL', () {
      expect(
        () => assertProductionBootConfig(
          databaseUrl: null,
          jwtSecret: 'k',
          isProd: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('and for a missing JWT_SECRET', () {
      // The reason this call exists rather than relying on the lazy `final`:
      // `tokenService` is only touched at boot when ADMIN_EMAIL/ADMIN_PASSWORD
      // are set. Otherwise the guard first runs on the FIRST REQUEST — after
      // the port is bound, after /health went green, after the orchestrator
      // marked the revision live and shifted traffic to it.
      expect(
        () => assertProductionBootConfig(
          databaseUrl: 'postgres://u:p@h:5432/db',
          jwtSecret: null,
          isProd: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a fully configured prod boot passes, and dev always passes', () {
      expect(
        () => assertProductionBootConfig(
          databaseUrl: 'postgres://u:p@h:5432/db',
          jwtSecret: 'k',
          isProd: true,
        ),
        returnsNormally,
      );
      expect(
        () => assertProductionBootConfig(
          databaseUrl: null,
          jwtSecret: null,
          isProd: false,
        ),
        returnsNormally,
        reason: 'every local run and the entire unit suite depends on this',
      );
    });
  });
}
