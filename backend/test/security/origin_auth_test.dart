import 'package:myweli_backend/src/security/origin_auth.dart';
import 'package:test/test.dart';

/// The origin gate's boot-time resolver — the five rows of the spec's §5.2,
/// each with the pair that stops « always throw » from passing.
///
/// Testable at all for the `boot_config` reason: `Platform.environment` is
/// immutable in-process, so the raw strings are arguments and the decision is
/// a value. Every refusal message must name the VARIABLE and never the value,
/// because `assertEveryDependencyResolves` prints them into the boot log.
///
/// Design: docs/design/infra-cloudflare-front-door.md §5.2, §8
void main() {
  const long = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEF'; // 42 chars
  const short = 'abcdefghijklmnopqrstuvwxyz01234'; // 31 chars — one under

  group('row 1 — secret unset or blank, not prod', () {
    test('→ OriginAuthOff, the middleware is inert', () {
      for (final raw in [null, '', '   ', '\t\n']) {
        expect(
          resolveOriginAuth(raw, null, isProd: false),
          isA<OriginAuthOff>(),
          reason: 'staging, dev and CI run without a Worker: "$raw"',
        );
      }
    });
  });

  group('row 2 — secret unset or blank, PROD', () {
    test('→ StateError naming ORIGIN_AUTH_SECRET', () {
      // Once the load balancer is gone an unset secret in production is an
      // open run.app door with a green /health — the exact shape the boot
      // guards exist to catch.
      for (final raw in [null, '', '   ']) {
        expect(
          () => resolveOriginAuth(raw, null, isProd: true),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('ORIGIN_AUTH_SECRET'),
            ),
          ),
          reason: 'a blank secret is unset, not a secret: "$raw"',
        );
      }
    });

    test('the dev pair: the same input off-prod does NOT throw', () {
      expect(
        resolveOriginAuth(null, null, isProd: false),
        isA<OriginAuthOff>(),
      );
    });
  });

  group('row 3 — secret present but shorter than 32', () {
    test('→ StateError in PROD', () {
      expect(
        () => resolveOriginAuth(short, null, isProd: true),
        throwsA(isA<StateError>()),
      );
    });

    test('→ StateError OFF-prod too — this refusal is not prod-only', () {
      // Unlike SMOKE_OTP_SECRET, where too-short means the feature stays off
      // (safe), a too-short gate secret means the door is guarded by something
      // guessable, or — if treated as absent — open. Both unsafe, everywhere.
      expect(
        () => resolveOriginAuth(short, null, isProd: false),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ORIGIN_AUTH_SECRET'),
          ),
        ),
      );
    });

    test('the message never contains the value', () {
      expect(
        () => resolveOriginAuth(short, null, isProd: false),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            isNot(contains(short)),
          ),
        ),
      );
    });

    test('exactly 32 is accepted — the boundary', () {
      const exact = '${short}x';
      expect(exact.length, kMinOriginAuthSecretLength);
      expect(resolveOriginAuth(exact, null, isProd: true), isA<OriginAuthOn>());
    });

    test('and the accepted secret is trimmed', () {
      final on =
          resolveOriginAuth('  $long  ', null, isProd: true) as OriginAuthOn;
      expect(on.secret, long);
    });
  });

  group('row 4 — mode unset', () {
    test('→ enforce, in prod and off-prod alike (the safe default)', () {
      for (final raw in [null, '', '  ']) {
        for (final isProd in [true, false]) {
          final on =
              resolveOriginAuth(long, raw, isProd: isProd) as OriginAuthOn;
          expect(
            on.mode,
            OriginAuthMode.enforce,
            reason:
                '`log` must be written down in the manifest to exist '
                '(mode="$raw", isProd=$isProd)',
          );
        }
      }
    });

    test('"log" and "enforce" are the two spellings, case-insensitive', () {
      expect(
        (resolveOriginAuth(long, 'log', isProd: true) as OriginAuthOn).mode,
        OriginAuthMode.log,
      );
      expect(
        (resolveOriginAuth(long, ' LOG ', isProd: true) as OriginAuthOn).mode,
        OriginAuthMode.log,
      );
      expect(
        (resolveOriginAuth(long, 'enforce', isProd: false) as OriginAuthOn)
            .mode,
        OriginAuthMode.enforce,
      );
    });
  });

  group('row 5 — mode is an unknown spelling', () {
    test('→ StateError naming ORIGIN_AUTH_MODE, in every environment', () {
      // The Env.parse rule: an unrecognised value never silently means
      // something. `off`, `true`, `1`, `warn` are the spellings a tired hand
      // would reach for, and each would otherwise pick a mode by accident.
      for (final raw in ['off', 'true', '1', 'warn', 'enforced']) {
        for (final isProd in [true, false]) {
          expect(
            () => resolveOriginAuth(long, raw, isProd: isProd),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('ORIGIN_AUTH_MODE'),
              ),
            ),
            reason: 'mode="$raw", isProd=$isProd',
          );
        }
      }
    });

    test('is refused even while the secret is unset', () {
      // A misspelled mode on a target that will later gain the secret would
      // otherwise be discovered on the day the secret lands.
      expect(
        () => resolveOriginAuth(null, 'warn', isProd: false),
        throwsA(isA<StateError>()),
      );
    });
  });
}
