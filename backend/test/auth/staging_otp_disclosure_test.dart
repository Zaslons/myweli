import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/smoke_seam.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/boot_config.dart';
import 'package:test/test.dart';

/// Staging must not hand out OTP codes.
///
/// **The defect this pins was live in production infrastructure**, not
/// hypothetical: `myweli-api-staging` runs `ingress: all` with `allUsers` as
/// invoker, its hostname is committed to a public repository, and
/// `devCode: _isProd ? null : code` meant anyone could ask for a code for any
/// address and read it out of the response — while a real `RESEND_API_KEY`
/// delivered the mail from `no-reply@myweli.com`, the launch domain.
///
/// It was a deliberate decision that expired. `Env`'s own comment justified the
/// echo on staging "because staging runs with no SMS channel and there would
/// otherwise be no way to sign in" — true when written, then staging got email,
/// Google and Apple, and nothing revisited the line.
///
/// So these tests assert the property (`staging discloses nothing`) rather than
/// the implementation, because the implementation is what drifted.
/// Design: docs/design/backend-staging-otp-disclosure.md.
void main() {
  TokenService ts() => TokenService(secret: 'test-secret-for-otp-disclosure');

  group('Env.echoesOtpDevCode', () {
    test('is true for dev only — staging and prod are deployed', () {
      expect(Env.dev.echoesOtpDevCode, isTrue);
      expect(
        Env.staging.echoesOtpDevCode,
        isFalse,
        reason: 'staging is public',
      );
      expect(Env.prod.echoesOtpDevCode, isFalse);
    });

    test('is a DIFFERENT question from isProd — that is the whole point', () {
      // If these ever coincide again the enum has lost the distinction and the
      // defect can come back by someone "simplifying" one into the other.
      expect(Env.staging.isProd, isFalse);
      expect(Env.staging.echoesOtpDevCode, isFalse);
      expect(
        Env.values.where((e) => !e.isProd).length,
        greaterThan(Env.values.where((e) => e.echoesOtpDevCode).length),
        reason: 'strictly fewer environments echo than are non-prod',
      );
    });

    test('guardsOn is unchanged — staging still fails fast on config', () {
      expect(Env.staging.guardsOn, isTrue);
    });
  });

  // Every repository, not one: fixing three of four would look identical from
  // any single route test, and the four are separate code paths (in-memory and
  // Postgres, consumer and provider).
  group('no repository echoes a code when the environment is deployed', () {
    test('consumer, in-memory', () async {
      final off = InMemoryAuthRepository(tokens: ts(), echoDevCode: false);
      final on = InMemoryAuthRepository(tokens: ts(), echoDevCode: true);
      expect((await off.requestEmailOtp('someone@gmail.com')).devCode, isNull);
      expect(
        (await on.requestEmailOtp('someone@gmail.com')).devCode,
        isNotNull,
      );
    });

    test('provider, in-memory', () async {
      final off = InMemoryProviderAuthRepository(
        tokens: ts(),
        echoDevCode: false,
      );
      final on = InMemoryProviderAuthRepository(
        tokens: ts(),
        echoDevCode: true,
      );
      expect((await off.requestOtp('+2250700000001')).devCode, isNull);
      expect((await on.requestOtp('+2250700000001')).devCode, isNotNull);
    });

    test(
      'the code itself is still ISSUED — only the disclosure stops',
      () async {
        // The distinction matters: suppressing the code entirely would break
        // email sign-in on staging, which is how a human gets in now that the
        // echo is gone.
        final off = InMemoryAuthRepository(tokens: ts(), echoDevCode: false);
        final r = await off.requestEmailOtp('someone@gmail.com');
        expect(r.ok, isTrue);
        expect(
          r.code,
          isNotNull,
          reason: 'the mail still needs a code to send',
        );
        expect(r.devCode, isNull, reason: 'but the caller must not see it');
      },
    );
  });

  group('the Q1b seam is the only remaining way in, on staging as on prod', () {
    const secret = 'a-secret-that-is-at-least-32-characters';

    test('discloses for a .test identity with the right secret', () {
      expect(
        smokeDisclosureAllowed(
          configuredSecret: secret,
          providedSecret: secret,
          identifier: 'client-1@smoke.test',
        ),
        isTrue,
      );
    });

    test('DENIES a real address even with the right secret', () {
      // The load-bearing half. A leaked secret must not buy a session on a
      // real person's address — the suffix is a compile-time constant that no
      // environment value can widen.
      expect(
        smokeDisclosureAllowed(
          configuredSecret: secret,
          providedSecret: secret,
          identifier: 'owner@gmail.com',
        ),
        isFalse,
      );
    });

    test('denies when staging has no secret configured — today\'s state', () {
      expect(
        smokeDisclosureAllowed(
          configuredSecret: null,
          providedSecret: secret,
          identifier: 'client-1@smoke.test',
        ),
        isFalse,
      );
    });
  });
}
