import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';

/// The mock's address change (B16.3b — account-email-change.md §3.1, §5.1,
/// §5.4): the demo and every screen test run on it, so it answers as the
/// server B16.3a deployed — one code per address shared with the sign-in, «
/// taken » said only after the right code and that code left for its owner,
/// decision 265's second code, and an address belonging to whoever proved it.
void main() {
  const code = MockAuthService.demoOtp;
  var n = 0;
  // Unique per test: MockData.users is static for the file.
  String address(String who) => '$who.${n++}@exemple.ci';

  Future<(MockAuthService, User)> signedInByCode(String email) async {
    final s = MockAuthService();
    await s.requestEmailOtp(email);
    final res = await s.verifyEmailOtp(email, code);
    expect(res.success, isTrue);
    return (s, res.data!);
  }

  test('a code sign-in makes a PROVEN account (decision 260)', () async {
    final (_, user) = await signedInByCode(address('awa'));
    expect(user.emailVerified, isTrue);
  });

  test(
    'an e-mail-code account: a code to each address, both asked (265)',
    () async {
      final old = address('awa');
      final next = address('awa.new');
      final (s, user) = await signedInByCode(old);

      final req = await s.requestEmailChange(next);
      expect(req.success, isTrue);
      expect(req.data!.currentCodeSent, isTrue);

      final missing = await s.confirmEmailChange(next, code);
      expect(missing.code, 'current_otp_none');

      final wrong = await s.confirmEmailChange(
        next,
        code,
        currentCode: '000000',
      );
      expect(wrong.code, 'current_otp_invalid');

      final done = await s.confirmEmailChange(next, code, currentCode: code);
      expect(done.success, isTrue);
      expect(done.data!.id, user.id);
      expect(done.data!.email, next);
      expect(done.data!.emailVerified, isTrue);
      expect((await s.getCurrentUser())!.email, next);

      // The old address no longer reaches the account.
      final other = MockAuthService();
      await other.requestEmailOtp(old);
      final again = await other.verifyEmailOtp(old, code);
      expect(again.data!.id, isNot(user.id));
    },
  );

  test('a Google account: one code, to the new address only', () async {
    final s = MockAuthService();
    await s.signInWithGoogle();
    final req = await s.requestEmailChange(address('g'));
    expect(req.data!.currentCodeSent, isFalse);
    expect(req.data!.currentDevCode, isNull);
  });

  test('by the link first: a Google account that changed its address still '
      'signs in with Google (§5.1)', () async {
    final s = MockAuthService();
    final first = (await s.signInWithGoogle()).data!;
    final next = address('g.new');
    await s.requestEmailChange(next);
    expect((await s.confirmEmailChange(next, code)).success, isTrue);

    final again = (await s.signInWithGoogle()).data!;

    expect(again.id, first.id, reason: 'the link, not the address, finds it');
    expect(again.email, next);
  });

  test('decision 265 is about links: a code account Google later links asks '
      'one code', () async {
    final s = MockAuthService();
    // The address the mock's Google asserts, first proven by a code.
    const googles = 'mock.google@myweli.test';
    await s.requestEmailOtp(googles);
    final byCode = (await s.verifyEmailOtp(googles, code)).data!;
    final unlinked = await s.requestEmailChange(address('x'));
    expect(unlinked.data!.currentCodeSent, isTrue);

    final linked = (await s.signInWithGoogle()).data!;
    expect(linked.id, byCode.id);
    final withLink = await s.requestEmailChange(address('y'));
    expect(withLink.data!.currentCodeSent, isFalse);
  });

  test('its own proven address: `email_unchanged`, at both steps', () async {
    final own = address('awa');
    final (s, _) = await signedInByCode(own);
    expect(
      (await s.requestEmailChange(own.toUpperCase())).code,
      'email_unchanged',
    );
    expect((await s.confirmEmailChange(own, code)).code, 'email_unchanged');
  });

  test('not an address: `invalid_email`', () async {
    final (s, _) = await signedInByCode(address('awa'));
    expect((await s.requestEmailChange('awa@')).code, 'invalid_email');
  });

  test('« taken » only after the right code, and that code still signs its '
      'owner in (decisions 262, §3.1)', () async {
    final owned = address('owner');
    final (_, owner) = await signedInByCode(owned);
    final s = MockAuthService();
    await s.signInWithGoogle();

    await s.requestEmailChange(owned);
    final wrong = await s.confirmEmailChange(owned, '000000');
    expect(
      wrong.code,
      'otp_invalid',
      reason: 'a wrong code learns nothing about the address',
    );

    final taken = await s.confirmEmailChange(owned, code);
    expect(taken.code, 'email_taken');
    expect(taken.error, kEmailTakenMessage);

    // The same code store (one mock, as one server): the owner's sign-in.
    final ownersSignIn = await s.verifyEmailOtp(owned, code);
    expect(ownersSignIn.success, isTrue, reason: 'the code was not consumed');
    expect(ownersSignIn.data!.id, owner.id);
  });

  test('a proof takes an address from an UNPROVEN holder', () async {
    final typed = address('typed');
    // An account that typed it in an older build, never proven.
    final holder = User(
      id: 'holder_${n++}',
      email: typed,
      createdAt: DateTime(2026),
    );
    MockData.users.add(holder);

    final s = MockAuthService();
    await s.signInWithGoogle();
    await s.requestEmailChange(typed);
    final done = await s.confirmEmailChange(typed, code);

    expect(done.success, isTrue);
    expect(done.data!.email, typed);
    expect(
      MockData.users.firstWhere((u) => u.id == holder.id).email,
      isNull,
      reason: 'an address belongs to whoever proved it (decision 260)',
    );
  });

  test(
    'a code sign-in never finds an UNPROVEN holder (decision 260)',
    () async {
      final typed = address('typed');
      final holder = User(
        id: 'holder_${n++}',
        email: typed,
        createdAt: DateTime(2026),
      );
      MockData.users.add(holder);

      final (_, owner) = await signedInByCode(typed);

      expect(owner.id, isNot(holder.id));
      expect(MockData.users.firstWhere((u) => u.id == holder.id).email, isNull);
    },
  );

  test('the change and the sign-in share one code per address', () async {
    final s = MockAuthService();
    await s.signInWithGoogle();
    final next = address('shared');
    await s.requestEmailChange(next);
    // A code proves an inbox, whatever it is then used for (§3.1): the
    // sign-in redeems the change's code.
    final signIn = await s.verifyEmailOtp(next, code);
    expect(signIn.success, isTrue);
    expect(signIn.data!.email, next);
  });

  test('`updateUser` keeps the address — it has no say over it', () async {
    final own = address('awa');
    final (s, _) = await signedInByCode(own);
    final res = await s.updateUser(name: 'Awa', phone: '');
    expect(res.data!.email, own);
    expect(res.data!.emailVerified, isTrue);
  });
}
