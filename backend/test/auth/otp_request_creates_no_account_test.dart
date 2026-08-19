import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:test/test.dart';

/// Requesting an OTP must create NO account.
///
/// **This exists because I claimed the opposite about production.** After
/// smoke-testing the live API with one `/auth/email/otp/request`, I reported
/// that production now held a junk *identity* needing a purge, and repeated the
/// same claim in the alert runbook about the 61-address budget probe. Both were
/// wrong: `INSERT INTO users` lives in `verifyEmailOtp`. Requesting a code
/// writes only `email_otp_codes`, five minutes out, and the probe never
/// verifies — so nothing was created on any environment either was pointed at.
///
/// The mistake is worth a test rather than a correction, because it is the
/// dangerous direction for a DIFFERENT reason than the one I was worried about:
/// if an unauthenticated caller ever COULD create a row in `users` by naming an
/// address, that is unbounded anonymous account creation on a public endpoint —
/// a far worse problem than the tidiness one I invented. The property is
/// security-relevant, it was unpinned, and it is cheap to pin.
void main() {
  late InMemoryAuthRepository repo;

  setUp(() {
    repo = InMemoryAuthRepository(
      tokens: TokenService(secret: 'test-secret'),
      echoDevCode: true,
    );
  });

  Future<int> userCount() async => (await repo.listUsers()).total;

  test(
    'no account exists before, during, or after a REQUEST-only flow',
    () async {
      expect(await userCount(), 0);

      for (var i = 0; i < 5; i++) {
        final r = await repo.requestEmailOtp('probe-$i@myweli.test');
        expect(r.ok, isTrue, reason: 'request $i was accepted');
      }

      expect(
        await userCount(),
        0,
        reason:
            'an anonymous caller naming five addresses must not have created five '
            'accounts — that would be unbounded account creation on a public '
            'endpoint',
      );
    },
  );

  test(
    '…and repeated requests for ONE address create nothing either',
    () async {
      for (var i = 0; i < 4; i++) {
        await repo.requestEmailOtp('same@myweli.test');
      }
      expect(await userCount(), 0);
    },
  );

  test('VERIFY is what creates the account — the control', () async {
    // Without this the test above passes just as happily against a repository
    // that never creates accounts at all, which would prove nothing about WHERE
    // creation happens.
    final requested = await repo.requestEmailOtp('real@example.test');
    expect(await userCount(), 0, reason: 'still nothing after the request');

    final verified = await repo.verifyEmailOtp(
      'real@example.test',
      requested.devCode!,
    );
    expect(verified.ok, isTrue, reason: 'the code was accepted');
    expect(verified.user, isNotNull);
    expect(
      await userCount(),
      1,
      reason: 'the account appears at VERIFY, which is the whole point',
    );
  });
}
