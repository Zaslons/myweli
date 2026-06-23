import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:test/test.dart';

void main() {
  TokenService ts() => TokenService(secret: 'test-secret');
  const phone = '+2250707010101';

  String wrong(String code) => code == '111111' ? '222222' : '111111';

  test('requestOtp returns a dev code outside prod, none in prod', () async {
    expect(
      (await InMemoryAuthRepository(
        tokens: ts(),
        isProd: false,
      ).requestOtp(phone)).devCode,
      isNotNull,
    );
    expect(
      (await InMemoryAuthRepository(
        tokens: ts(),
        isProd: true,
      ).requestOtp(phone)).devCode,
      isNull,
    );
  });

  test('resend budget is enforced', () async {
    final repo = InMemoryAuthRepository(
      tokens: ts(),
      isProd: false,
      maxResends: 1,
    );
    expect((await repo.requestOtp(phone)).ok, isTrue);
    expect((await repo.requestOtp(phone)).ok, isTrue);
    final third = await repo.requestOtp(phone);
    expect(third.ok, isFalse);
    expect(third.error, 'otp_resend_limit');
  });

  test('verifyOtp succeeds with the right code and issues tokens', () async {
    final repo = InMemoryAuthRepository(tokens: ts(), isProd: false);
    final code = (await repo.requestOtp(phone)).devCode!;
    final res = await repo.verifyOtp(phone, code);
    expect(res.ok, isTrue);
    expect(res.user!.phoneNumber, phone);
    expect(res.tokens!.accessToken, isNotEmpty);
    expect(res.tokens!.refreshToken, isNotEmpty);
  });

  test('same phone resolves to the same user (find-or-create)', () async {
    final repo = InMemoryAuthRepository(tokens: ts(), isProd: false);
    final id1 = (await repo.verifyOtp(
      phone,
      (await repo.requestOtp(phone)).devCode!,
    )).user!.id;
    final id2 = (await repo.verifyOtp(
      phone,
      (await repo.requestOtp(phone)).devCode!,
    )).user!.id;
    expect(id1, id2);
  });

  test('wrong codes decrement the budget then lock out', () async {
    final repo = InMemoryAuthRepository(
      tokens: ts(),
      isProd: false,
      maxAttempts: 2,
    );
    final code = (await repo.requestOtp(phone)).devCode!;
    expect((await repo.verifyOtp(phone, wrong(code))).error, 'otp_invalid');
    expect((await repo.verifyOtp(phone, wrong(code))).error, 'otp_locked');
  });

  test('expired codes are rejected', () async {
    final repo = InMemoryAuthRepository(
      tokens: ts(),
      isProd: false,
      otpValidity: const Duration(milliseconds: 1),
    );
    final code = (await repo.requestOtp(phone)).devCode!;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await repo.verifyOtp(phone, code)).error, 'otp_expired');
  });

  test(
    'refresh rotates, and replaying a rotated token revokes the family',
    () async {
      final repo = InMemoryAuthRepository(tokens: ts(), isProd: false);
      final first = (await repo.verifyOtp(
        phone,
        (await repo.requestOtp(phone)).devCode!,
      )).tokens!;

      final rotated = await repo.refresh(first.refreshToken);
      expect(rotated.ok, isTrue);
      final second = rotated.tokens!.refreshToken;

      // Replay the now-rotated first token → reuse detected, family revoked.
      final reuse = await repo.refresh(first.refreshToken);
      expect(reuse.ok, isFalse);
      expect(reuse.error, 'refresh_reused');

      // The rotated-out second token is now dead too (family revoked).
      final after = await repo.refresh(second);
      expect(after.ok, isFalse);
      expect(after.error, 'refresh_invalid');
    },
  );

  test('updateUser mutates fields; deleteUser removes the account', () async {
    final repo = InMemoryAuthRepository(tokens: ts(), isProd: false);
    final user = (await repo.verifyOtp(
      phone,
      (await repo.requestOtp(phone)).devCode!,
    )).user!;

    final updated = await repo.updateUser(
      user.id,
      name: 'Awa',
      email: 'a@b.ci',
    );
    expect(updated!.name, 'Awa');
    expect(updated.email, 'a@b.ci');
    expect((await repo.updateUser(user.id, email: ''))!.email, isNull);

    expect(await repo.deleteUser(user.id), isTrue);
    expect(await repo.userById(user.id), isNull);
    expect(await repo.deleteUser(user.id), isFalse);
  });
}
