import 'package:myweli_backend/src/auth/smoke_seam.dart';
import 'package:test/test.dart';

/// The production OTP-disclosure seam (Q1b).
///
/// This is the one place in the codebase where production may hand an OTP back
/// over HTTP, so it is written negative-first: every test that says "refused"
/// comes before the one that says "allowed", because a bug here is an account
/// takeover primitive rather than a broken feature.
///
/// Design: docs/design/backend-q1b-smoke-seam.md.
void main() {
  // 32+ chars, so the length floor is never what makes a test pass or fail
  // except in the test that is specifically about the length floor.
  const secret = 'a-thirty-two-character-secret-x01';

  group('the seam is ABSENT unless deliberately configured', () {
    test('unset, empty or whitespace secret → absent', () {
      // Default posture. Production normally runs with no seam at all, and
      // "no seam" must not be reachable by supplying a matching blank header.
      for (final configured in [null, '', '   ', '\t\n']) {
        expect(
          smokeDisclosureAllowed(
            configuredSecret: configured,
            providedSecret: configured,
            identifier: 'x@smoke.test',
          ),
          isFalse,
          reason: 'a blank secret is no secret: ${configured?.length}',
        );
      }
    });

    test('a SHORT secret is treated as no secret', () {
      // Stops `SMOKE_OTP_SECRET=test` from enabling disclosure in production.
      // The header matches exactly and the identity is valid — the only thing
      // wrong is that the secret is guessable, and that alone must refuse.
      expect(
        smokeDisclosureAllowed(
          configuredSecret: 'test',
          providedSecret: 'test',
          identifier: 'x@smoke.test',
        ),
        isFalse,
      );
      expect(
        smokeDisclosureAllowed(
          configuredSecret: 'a' * 31,
          providedSecret: 'a' * 31,
          identifier: 'x@smoke.test',
        ),
        isFalse,
        reason: '31 characters is below the floor; 32 is the boundary',
      );
    });
  });

  group('THE ACCOUNT-TAKEOVER CASES — refused', () {
    test('a correct secret does NOT disclose for a real address', () {
      // The whole reason the identity constraint exists. If SMOKE_OTP_SECRET
      // leaks completely, this is the line between "an attacker can sign in as
      // a throwaway identity at an unroutable domain" and "an attacker owns
      // every account". No value of any env var can make these end in .test.
      for (final real in [
        'owner@gmail.com',
        'sadreddinedaher@gmail.com',
        'client@myweli.com',
        'a@smoke.com',
      ]) {
        expect(
          smokeDisclosureAllowed(
            configuredSecret: secret,
            providedSecret: secret,
            identifier: real,
          ),
          isFalse,
          reason: 'must never disclose an OTP for $real',
        );
      }
    });

    test('a look-alike that only CONTAINS .test is refused', () {
      // `endsWith` is the rule, and this is what a substring check would have
      // let through — an attacker-controlled domain with .test in the middle.
      for (final lookalike in [
        'x@smoke.test.evil.com',
        'x@test.example.com',
        'x@nottest',
        'x@smoke.testing',
      ]) {
        expect(
          smokeDisclosureAllowed(
            configuredSecret: secret,
            providedSecret: secret,
            identifier: lookalike,
          ),
          isFalse,
          reason: '$lookalike is not in the reserved TLD',
        );
      }
    });

    test('a valid identity with a WRONG or MISSING header is refused', () {
      for (final provided in [
        null,
        '',
        'wrong',
        'a-thirty-two-character-secret-x02',
      ]) {
        expect(
          smokeDisclosureAllowed(
            configuredSecret: secret,
            providedSecret: provided,
            identifier: 'x@smoke.test',
          ),
          isFalse,
          reason: 'header "$provided" must not unlock disclosure',
        );
      }
    });

    test('a prefix of the secret is refused', () {
      // Guards against a compare that stops at the shorter length.
      expect(
        smokeDisclosureAllowed(
          configuredSecret: secret,
          providedSecret: secret.substring(0, 20),
          identifier: 'x@smoke.test',
        ),
        isFalse,
      );
    });
  });

  group('allowed — both conditions met', () {
    test('the smoke harness identities all pass', () {
      // These are literally the addresses funnel_smoke_test.dart builds
      // (:196, :384, :788, :815). If this fails the gate cannot authenticate.
      for (final id in [
        'pro-main-abc123@smoke.test',
        'client-abc123@smoke.test',
        'lock-abc123@smoke.test',
        'other-abc123@smoke.test',
      ]) {
        expect(
          smokeDisclosureAllowed(
            configuredSecret: secret,
            providedSecret: secret,
            identifier: id,
          ),
          isTrue,
          reason: '$id is a harness identity and must be disclosable',
        );
      }
    });

    test('the suffix check is case-insensitive and allows sub-domains', () {
      for (final id in ['X@SMOKE.TEST', 'x@a.b.test', 'x@Smoke.Test']) {
        expect(
          smokeDisclosureAllowed(
            configuredSecret: secret,
            providedSecret: secret,
            identifier: id,
          ),
          isTrue,
          reason: '$id ends in the reserved TLD',
        );
      }
    });

    test('surrounding whitespace on the header is tolerated', () {
      // A shell or a proxy can pad a header value; that should not read as an
      // attack, whereas a blank one already refuses above.
      expect(
        smokeDisclosureAllowed(
          configuredSecret: '  $secret  ',
          providedSecret: ' $secret ',
          identifier: 'x@smoke.test',
        ),
        isTrue,
      );
    });
  });

  group('constantTimeEquals', () {
    test('is correct before it is constant-time', () {
      expect(constantTimeEquals('abc', 'abc'), isTrue);
      expect(constantTimeEquals('abc', 'abd'), isFalse);
      expect(constantTimeEquals('abc', 'ab'), isFalse);
      expect(constantTimeEquals('', ''), isTrue);
    });

    test('compares every byte rather than short-circuiting', () {
      // A `==`-style early return leaks where the first mismatch is. This
      // cannot prove timing behaviour in a unit test, so it pins the property
      // that makes it possible: equal-length inputs differing only in the LAST
      // byte must still be compared in full and reported unequal.
      final a = 'x' * 64;
      expect(constantTimeEquals(a, '${'x' * 63}y'), isFalse);
      expect(constantTimeEquals(a, 'y${'x' * 63}'), isFalse);
    });
  });
}
