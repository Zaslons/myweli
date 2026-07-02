import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:test/test.dart';

void main() {
  TokenService ts() => TokenService(secret: 'test-secret');
  InMemoryAuthRepository repo({
    bool isProd = false,
    Duration otpValidity = const Duration(minutes: 5),
    int maxAttempts = 5,
    int maxResends = 3,
  }) => InMemoryAuthRepository(
    tokens: ts(),
    isProd: isProd,
    otpValidity: otpValidity,
    maxAttempts: maxAttempts,
    maxResends: maxResends,
  );

  group('loginWithSocial', () {
    test('creates a user with verified email + provider claims', () async {
      final r = repo();
      final res = await r.loginWithSocial(
        provider: 'google',
        sub: 'g1',
        email: 'Ama@Example.com',
        emailVerified: true,
        name: 'Ama',
        avatarUrl: 'https://p/a.png',
      );
      expect(res.ok, isTrue);
      expect(res.tokens!.accessToken, isNotEmpty);
      final u = res.user!;
      expect(u.email, 'ama@example.com');
      expect(u.emailVerified, isTrue);
      expect(u.authProvider, 'google');
      expect(u.phoneNumber, isNull);
      expect(u.phoneVerified, isFalse);
    });

    test('same sub resolves to the same user', () async {
      final r = repo();
      final a = await r.loginWithSocial(
        provider: 'google',
        sub: 'g1',
        email: 'a@x.com',
        emailVerified: true,
      );
      final b = await r.loginWithSocial(
        provider: 'google',
        sub: 'g1',
        email: 'a@x.com',
        emailVerified: true,
      );
      expect(b.user!.id, a.user!.id);
    });

    test('verified email links to the existing email-OTP account', () async {
      final r = repo();
      final code = (await r.requestEmailOtp('ama@x.com')).devCode!;
      final emailUser = (await r.verifyEmailOtp('ama@x.com', code)).user!;
      final social = await r.loginWithSocial(
        provider: 'google',
        sub: 'g9',
        email: 'Ama@X.com',
        emailVerified: true,
        name: 'Ama',
      );
      expect(social.user!.id, emailUser.id, reason: 'linked, not duplicated');
      expect(social.user!.name, 'Ama', reason: 'fills missing profile fields');
    });

    test('UNVERIFIED email never links (T33) — separate account', () async {
      final r = repo();
      final code = (await r.requestEmailOtp('ama@x.com')).devCode!;
      final emailUser = (await r.verifyEmailOtp('ama@x.com', code)).user!;
      final social = await r.loginWithSocial(
        provider: 'apple',
        sub: 'a1',
        email: 'ama@x.com',
        emailVerified: false,
      );
      expect(social.ok, isTrue);
      expect(social.user!.id, isNot(emailUser.id));
    });

    test('banned account → account_suspended, no tokens', () async {
      final r = repo();
      final first = await r.loginWithSocial(
        provider: 'google',
        sub: 'g1',
        email: 'a@x.com',
        emailVerified: true,
      );
      await r.setStatus(first.user!.id, 'banned');
      final again = await r.loginWithSocial(
        provider: 'google',
        sub: 'g1',
        email: 'a@x.com',
        emailVerified: true,
      );
      expect(again.ok, isFalse);
      expect(again.error, 'account_suspended');
      expect(again.tokens, isNull);
    });
  });

  group('email OTP', () {
    test('devCode outside prod only', () async {
      expect((await repo().requestEmailOtp('a@x.com')).devCode, isNotNull);
      expect(
        (await repo(isProd: true).requestEmailOtp('a@x.com')).devCode,
        isNull,
      );
    });

    test('verify creates a user with a VERIFIED email', () async {
      final r = repo();
      final code = (await r.requestEmailOtp('a@x.com')).devCode!;
      final res = await r.verifyEmailOtp('a@x.com', code);
      expect(res.ok, isTrue);
      expect(res.user!.email, 'a@x.com');
      expect(res.user!.emailVerified, isTrue);
      expect(res.user!.authProvider, 'email');
    });

    test('email is case-insensitive (one account)', () async {
      final r = repo();
      final c1 = (await r.requestEmailOtp('Ama@X.com')).devCode!;
      final id1 = (await r.verifyEmailOtp('Ama@X.com', c1)).user!.id;
      final c2 = (await r.requestEmailOtp('ama@x.com')).devCode!;
      final id2 = (await r.verifyEmailOtp('ama@x.com', c2)).user!.id;
      expect(id2, id1);
    });

    test('wrong code exhausts attempts → otp_locked', () async {
      final r = repo(maxAttempts: 2);
      final code = (await r.requestEmailOtp('a@x.com')).devCode!;
      final bad = code == '111111' ? '222222' : '111111';
      expect((await r.verifyEmailOtp('a@x.com', bad)).error, 'otp_invalid');
      expect((await r.verifyEmailOtp('a@x.com', bad)).error, 'otp_locked');
      // Even the right code is refused once locked.
      expect((await r.verifyEmailOtp('a@x.com', code)).error, 'otp_locked');
    });

    test('resend budget → otp_resend_limit', () async {
      final r = repo(maxResends: 1);
      expect((await r.requestEmailOtp('a@x.com')).ok, isTrue);
      expect((await r.requestEmailOtp('a@x.com')).ok, isTrue);
      final third = await r.requestEmailOtp('a@x.com');
      expect(third.ok, isFalse);
      expect(third.error, 'otp_resend_limit');
    });

    test('expired code → otp_expired', () async {
      final r = repo(otpValidity: Duration.zero);
      final code = (await r.requestEmailOtp('a@x.com')).devCode!;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect((await r.verifyEmailOtp('a@x.com', code)).error, 'otp_expired');
    });

    test('no pending code → otp_none', () async {
      expect(
        (await repo().verifyEmailOtp('a@x.com', '123456')).error,
        'otp_none',
      );
    });
  });

  group('phone → contact attribute', () {
    test('updateUser sets an UNVERIFIED contact phone; empty clears', () async {
      final r = repo();
      final code = (await r.requestEmailOtp('a@x.com')).devCode!;
      final user = (await r.verifyEmailOtp('a@x.com', code)).user!;
      final withPhone = await r.updateUser(user.id, phone: '+2250700000001');
      expect(withPhone!.phoneNumber, '+2250700000001');
      expect(withPhone.phoneVerified, isFalse);
      final cleared = await r.updateUser(user.id, phone: '');
      expect(cleared!.phoneNumber, isNull);
    });

    test('phone OTP still marks the phone verified (dormant path)', () async {
      final r = repo();
      const phone = '+2250707010101';
      final code = (await r.requestOtp(phone)).devCode!;
      final res = await r.verifyOtp(phone, code);
      expect(res.user!.phoneVerified, isTrue);
      expect(res.user!.authProvider, 'phone');
    });

    test('changing email resets emailVerified', () async {
      final r = repo();
      final code = (await r.requestEmailOtp('a@x.com')).devCode!;
      final user = (await r.verifyEmailOtp('a@x.com', code)).user!;
      final changed = await r.updateUser(user.id, email: 'b@x.com');
      expect(changed!.email, 'b@x.com');
      expect(changed.emailVerified, isFalse);
    });
  });
}
