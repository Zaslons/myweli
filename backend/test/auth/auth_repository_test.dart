import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:test/test.dart';

void main() {
  TokenService ts() => TokenService(secret: 'test-secret');
  const phone = '+2250707010101';

  String wrong(String code) => code == '111111' ? '222222' : '111111';

  test('requestOtp returns a dev code outside prod, none in prod', () {
    expect(
      InMemoryAuthRepository(
        tokens: ts(),
        isProd: false,
      ).requestOtp(phone).devCode,
      isNotNull,
    );
    expect(
      InMemoryAuthRepository(
        tokens: ts(),
        isProd: true,
      ).requestOtp(phone).devCode,
      isNull,
    );
  });

  test('resend budget is enforced', () {
    final repo = InMemoryAuthRepository(
      tokens: ts(),
      isProd: false,
      maxResends: 1,
    );
    expect(repo.requestOtp(phone).ok, isTrue);
    expect(repo.requestOtp(phone).ok, isTrue);
    final third = repo.requestOtp(phone);
    expect(third.ok, isFalse);
    expect(third.error, 'otp_resend_limit');
  });

  test('verifyOtp succeeds with the right code and issues tokens', () {
    final repo = InMemoryAuthRepository(tokens: ts(), isProd: false);
    final code = repo.requestOtp(phone).devCode!;
    final res = repo.verifyOtp(phone, code);
    expect(res.ok, isTrue);
    expect(res.user!.phoneNumber, phone);
    expect(res.tokens!.accessToken, isNotEmpty);
    expect(res.tokens!.refreshToken, isNotEmpty);
  });

  test('same phone resolves to the same user (find-or-create)', () {
    final repo = InMemoryAuthRepository(tokens: ts(), isProd: false);
    final id1 = repo.verifyOtp(phone, repo.requestOtp(phone).devCode!).user!.id;
    final id2 = repo.verifyOtp(phone, repo.requestOtp(phone).devCode!).user!.id;
    expect(id1, id2);
  });

  test('wrong codes decrement the budget then lock out', () {
    final repo = InMemoryAuthRepository(
      tokens: ts(),
      isProd: false,
      maxAttempts: 2,
    );
    final code = repo.requestOtp(phone).devCode!;
    expect(repo.verifyOtp(phone, wrong(code)).error, 'otp_invalid');
    expect(repo.verifyOtp(phone, wrong(code)).error, 'otp_locked');
  });

  test('expired codes are rejected', () async {
    final repo = InMemoryAuthRepository(
      tokens: ts(),
      isProd: false,
      otpValidity: const Duration(milliseconds: 1),
    );
    final code = repo.requestOtp(phone).devCode!;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repo.verifyOtp(phone, code).error, 'otp_expired');
  });

  test('refresh rotates, and replaying a rotated token revokes the family', () {
    final repo = InMemoryAuthRepository(tokens: ts(), isProd: false);
    final first = repo
        .verifyOtp(phone, repo.requestOtp(phone).devCode!)
        .tokens!;

    final rotated = repo.refresh(first.refreshToken);
    expect(rotated.ok, isTrue);
    final second = rotated.tokens!.refreshToken;

    // Replay the now-rotated first token → reuse detected, family revoked.
    final reuse = repo.refresh(first.refreshToken);
    expect(reuse.ok, isFalse);
    expect(reuse.error, 'refresh_reused');

    // The rotated-out second token is now dead too (family revoked).
    final after = repo.refresh(second);
    expect(after.ok, isFalse);
    expect(after.error, 'refresh_invalid');
  });

  test('updateUser mutates fields; deleteUser removes the account', () {
    final repo = InMemoryAuthRepository(tokens: ts(), isProd: false);
    final user = repo.verifyOtp(phone, repo.requestOtp(phone).devCode!).user!;

    final updated = repo.updateUser(user.id, name: 'Awa', email: 'a@b.ci');
    expect(updated!.name, 'Awa');
    expect(updated.email, 'a@b.ci');
    expect(repo.updateUser(user.id, email: '')!.email, isNull);

    expect(repo.deleteUser(user.id), isTrue);
    expect(repo.userById(user.id), isNull);
    expect(repo.deleteUser(user.id), isFalse);
  });
}
