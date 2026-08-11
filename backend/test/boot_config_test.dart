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
        () => resolveDatabaseUrl(null, guardsOn: true),
        throwsA(isA<StateError>()),
      );
    });

    test('production with an EMPTY or whitespace URL also refuses', () {
      // A platform that injects an unset reference hands you '' or padding —
      // which the old code passed straight to createPool as a real value.
      for (final raw in ['', '   ', '\t\n']) {
        expect(
          () => resolveDatabaseUrl(raw, guardsOn: true),
          throwsA(isA<StateError>()),
          reason: 'a blank URL is unset, not a connection string: "$raw"',
        );
      }
    });

    test('production WITH a URL starts, and the value is trimmed', () {
      expect(
        resolveDatabaseUrl('  postgres://u:p@h:5432/db  ', guardsOn: true),
        'postgres://u:p@h:5432/db',
      );
    });

    test('DEV with no URL still runs in-memory — the pair', () {
      // Without this, "always throw" would satisfy every assertion above and
      // break every local run and the whole unit suite, which has no database.
      expect(resolveDatabaseUrl(null, guardsOn: false), isNull);
      expect(resolveDatabaseUrl('', guardsOn: false), isNull);
    });
  });

  group('JWT_SECRET', () {
    test('production with no secret refuses to start', () {
      expect(
        () => resolveJwtSecret(null, guardsOn: true),
        throwsA(isA<StateError>()),
      );
    });

    test('dev falls back, and the fallback is never a real secret', () {
      final s = resolveJwtSecret(null, guardsOn: false);
      expect(s, isNotEmpty);
      expect(
        s,
        contains('dev'),
        reason: 'the dev fallback must be self-evidently not a production key',
      );
    });

    test('a supplied secret wins in both modes', () {
      expect(resolveJwtSecret(' k ', guardsOn: true), 'k');
      expect(resolveJwtSecret(' k ', guardsOn: false), 'k');
    });
  });

  group('assertProductionBootConfig — why the guards fire at BOOT', () {
    test('it throws for a missing DATABASE_URL', () {
      expect(
        () => assertProductionBootConfig(
          databaseUrl: null,
          jwtSecret: 'k',
          guardsOn: true,
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
          guardsOn: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a fully configured prod boot passes, and dev always passes', () {
      expect(
        () => assertProductionBootConfig(
          databaseUrl: 'postgres://u:p@h:5432/db',
          jwtSecret: 'k',
          guardsOn: true,
        ),
        returnsNormally,
      );
      expect(
        () => assertProductionBootConfig(
          databaseUrl: null,
          jwtSecret: null,
          guardsOn: false,
        ),
        returnsNormally,
        reason: 'every local run and the entire unit suite depends on this',
      );
    });
  });

  /// `ENV` as a three-value enum (docs/design/infra-staging.md §1.1).
  ///
  /// The old read was `(ENV ?? 'dev') == 'prod'` — one boolean answering two
  /// questions. These tests pin the split, and the typo case that the old
  /// expression silently swallowed.
  group('Env.parse', () {
    test('unset, empty and whitespace mean dev', () {
      for (final raw in [null, '', '   ', '\t\n']) {
        expect(Env.parse(raw), Env.dev, reason: 'raw: ${raw?.trim()}');
      }
    });

    test('each environment parses, case- and whitespace-insensitively', () {
      expect(Env.parse('dev'), Env.dev);
      expect(Env.parse('development'), Env.dev);
      expect(Env.parse('local'), Env.dev);
      expect(Env.parse('staging'), Env.staging);
      expect(Env.parse('stage'), Env.staging);
      expect(Env.parse('  STAGING  '), Env.staging);
      expect(Env.parse('prod'), Env.prod);
      expect(Env.parse('production'), Env.prod);
      expect(Env.parse('  Prod '), Env.prod);
    });

    test('an unrecognised value THROWS rather than meaning dev', () {
      // The failure this exists to prevent: under the old expression, `ENV=prd`
      // on the production service silently disabled every guard in
      // dependencies.dart — fail-fast on DATABASE_URL and JWT_SECRET, the R2 /
      // messaging / push / OAuth config checks, and CORS deny-by-default. A
      // typo, and production quietly becomes dev.
      for (final raw in ['prd', 'produciton', 'PRODUCTION_', 'test', 'qa']) {
        expect(
          () => Env.parse(raw),
          throwsA(isA<StateError>()),
          reason: 'unknown ENV must not degrade to dev: "$raw"',
        );
      }
    });
  });

  group('guardsOn vs isProd — the split that makes staging possible', () {
    test('guards run in staging AND prod, never in dev', () {
      expect(Env.dev.guardsOn, isFalse);
      expect(Env.staging.guardsOn, isTrue);
      expect(Env.prod.guardsOn, isTrue);
    });

    test('isProd is prod ALONE — staging must not be the real thing', () {
      expect(Env.dev.isProd, isFalse);
      expect(Env.staging.isProd, isFalse);
      expect(Env.prod.isProd, isTrue);
    });

    test('staging fails fast on missing config exactly as production does', () {
      // This is the property that makes staging a rehearsal rather than a
      // second dev environment. `ENV=staging` against the old boolean turned
      // every one of these guards OFF.
      expect(
        () => resolveDatabaseUrl(null, guardsOn: Env.staging.guardsOn),
        throwsA(isA<StateError>()),
      );
      expect(
        () => resolveJwtSecret(null, guardsOn: Env.staging.guardsOn),
        throwsA(isA<StateError>()),
      );
      expect(
        () => assertProductionBootConfig(
          databaseUrl: null,
          jwtSecret: null,
          guardsOn: Env.staging.guardsOn,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('dev still boots with nothing configured', () {
      // The local loop must stay zero-setup — that is the whole reason the
      // guards are conditional rather than unconditional.
      expect(resolveDatabaseUrl(null, guardsOn: Env.dev.guardsOn), isNull);
      expect(
        resolveJwtSecret(null, guardsOn: Env.dev.guardsOn),
        isNotEmpty,
        reason: 'dev falls back to the insecure placeholder',
      );
    });
  });
}
