import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:test/test.dart';

/// The e-mail code at a Pro sign-up, run against BOTH twins: in memory
/// (`pro_auth_contracts_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`, which also forces the races of
/// §8.2). Not a test file itself.
///
/// docs/design/auth-store-twins.md §5.2 (B16.4, decision 285). A refused
/// sign-up keeps its code; only the account a code creates spends it; a
/// wrong guess costs an attempt; a Google or Apple sign-up leaves a pending
/// code alone. The same for `register` and `createMemberAccount` (an invited
/// member).
void proSignupCodeContract({
  required ProviderAuthRepository Function() repo,
  // A store whose codes are born expired (a negative validity, so no clock
  // skew between Dart and the database can make it flake).
  required ProviderAuthRepository Function() expiring,
}) {
  final run = DateTime.now().microsecondsSinceEpoch;
  var n = 0;
  String address(String who) => '$who.${run}_${n++}@b164.test';

  final paths =
      <
        String,
        Future<ProviderVerifyResult> Function(
          ProviderAuthRepository r,
          String email,
          String code,
        )
      >{
        'register': (r, email, code) => r.register(
          businessName: 'B16.4',
          businessType: 'salon',
          phoneNumber: '+2250700000001',
          email: email,
          authProvider: 'email',
          emailCode: code,
        ),
        'createMemberAccount': (r, email, code) => r.createMemberAccount(
          email: email,
          authProvider: 'email',
          emailCode: code,
        ),
      };

  Future<String> codeFor(ProviderAuthRepository r, String email) async =>
      (await r.requestEmailOtp(email)).devCode!;

  for (final MapEntry(key: name, value: signUp) in paths.entries) {
    test('[kept on a refusal] $name on a taken X with a right code: '
        'provider_exists, and that code then signs in A', () async {
      final r = repo();
      final x = address('kept');
      final a = (await signUp(r, x, await codeFor(r, x))).provider!;
      final code = await codeFor(r, x);

      final again = await signUp(r, x, code);
      expect(again.error, 'provider_exists');

      final v = await r.verifyEmailOtp(x, code);
      expect(
        v.ok,
        isTrue,
        reason:
            '[kept on a refusal] a refused sign-up cost the code: '
            '${v.error}',
      );
      expect(v.provider!.id, a.id);
    });

    test('[the code first] $name on a taken X with a WRONG code: '
        'otp_invalid, never provider_exists (no enumeration, T32)', () async {
      final r = repo();
      final x = address('first');
      final created = await signUp(r, x, await codeFor(r, x));
      expect(created.ok, isTrue, reason: 'the premise: ${created.error}');
      final code = await codeFor(r, x);
      final wrong = code == '000000' ? '111111' : '000000';
      expect(
        (await signUp(r, x, wrong)).error,
        'otp_invalid',
        reason:
            '[the code first] a taken address was answered before the '
            'code was checked',
      );
    });

    test('[the code first] $name on a taken X with no code pending: '
        'otp_none, never provider_exists', () async {
      final r = repo();
      final x = address('none');
      final created = await signUp(r, x, await codeFor(r, x));
      expect(created.ok, isTrue, reason: 'the premise: ${created.error}');
      expect(
        (await signUp(r, x, '123456')).error,
        'otp_none',
        reason:
            '[the code first] a taken address was answered before the '
            'code was checked',
      );
    });

    test('[spent by the creation] $name: the code that created A, on X '
        'again, answers otp_none', () async {
      final r = repo();
      final x = address('spent');
      final code = await codeFor(r, x);
      final created = await signUp(r, x, code);
      expect(created.ok, isTrue, reason: 'the premise: ${created.error}');

      final v = await r.verifyEmailOtp(x, code);
      expect(
        v.error,
        'otp_none',
        reason: '[spent by the creation] the code survived its own creation',
      );
    });
  }

  test('[attempts] wrong guesses each cost an attempt; at none left the '
      'right code is refused too (a control)', () async {
    final r = repo();
    final x = address('attempts');
    final code = await codeFor(r, x);
    final wrong = code == '000000' ? '111111' : '000000';
    final signUp = paths['register']!;
    final answers = [
      for (var i = 0; i < 5; i++) (await signUp(r, x, wrong)).error,
    ];
    expect(answers, [
      'otp_invalid',
      'otp_invalid',
      'otp_invalid',
      'otp_invalid',
      'otp_locked',
    ]);
    expect((await signUp(r, x, code)).error, 'otp_locked');
  });

  test('[expired] a code past its validity answers otp_expired and is '
      'deleted, at the sign-in and at the sign-up', () async {
    final r = expiring();
    final x = address('expired');
    final code = await codeFor(r, x);
    expect((await r.verifyEmailOtp(x, code)).error, 'otp_expired');
    expect(
      (await r.verifyEmailOtp(x, code)).error,
      'otp_none',
      reason: '[expired] an expired code must be deleted',
    );
    final again = await codeFor(r, x);
    expect((await paths['register']!(r, x, again)).error, 'otp_expired');
    expect((await paths['register']!(r, x, again)).error, 'otp_none');
  });

  test(
    '[a social sign-up leaves the code] a pending code for X, then a '
    'Google sign-up on X: the code then signs into the new account',
    () async {
      final r = repo();
      final x = address('social');
      final code = await codeFor(r, x);
      final g = await r.register(
        businessName: 'B16.4',
        businessType: 'salon',
        phoneNumber: '+2250700000001',
        email: x,
        authProvider: 'google',
        googleSub: 'g-$run-${n++}',
      );
      expect(g.ok, isTrue, reason: 'the premise: ${g.error}');

      final v = await r.verifyEmailOtp(x, code);
      expect(
        v.ok,
        isTrue,
        reason:
            '[a social sign-up leaves the code] the Google sign-up '
            'deleted the pending code: ${v.error}',
      );
      expect(v.provider!.id, g.provider!.id);
    },
  );
}
