import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:myweli_backend/src/upload_verification_service.dart';
import 'package:test/test.dart';

import '../../routes/me/index.dart' as me_route;

class _Ctx extends Mock implements RequestContext {}

/// Puts [email] on account [userId] **unproven**, the state a profile edit
/// left before B16.3 and the state such accounts keep in production. Each
/// twin does it its own way (the in-memory twin through a test seam, Postgres
/// by SQL), because after B16.3 no route writes an unproven address.
typedef PlantUnproven =
    Future<void> Function(AuthRepository repo, String userId, String email);

/// An account's e-mail, run against BOTH twins: in memory
/// (`account_email_test.dart`) and Postgres (`db/postgres_repositories_test.dart`).
/// Not a test file itself.
///
/// docs/design/account-email-change.md §2.4, §5.1, §5.5 (B16.3, decisions
/// 260–265). An address reaches an account only once that account proved it;
/// a proof takes an unproven address from whoever holds it; a Google or Apple
/// link is never replaced; `PATCH /me` no longer changes or clears it.
///
/// Each case says, in brackets, the row of the spec's table it pins (P1–P6)
/// or the rule (§5.1), so a red names its reason. Addresses are unique per
/// run, in the RFC 2606 `.test` TLD.
void accountEmailContract({
  required AuthRepository Function() repo,
  required PlantUnproven plant,
}) {
  final tokens = TokenService(secret: 'test-secret');
  final run = DateTime.now().microsecondsSinceEpoch;
  var n = 0;
  String address(String who) => '$who.${run}_${n++}@b163.test';
  String sub(String who) => '$who-${run}_${n++}';

  Future<AuthUser> byCode(AuthRepository r, String email) async {
    final code = (await r.requestEmailOtp(email)).devCode!;
    final v = await r.verifyEmailOtp(email, code);
    expect(v.ok, isTrue, reason: 'the code sign-in itself failed: ${v.error}');
    return v.user!;
  }

  Future<AuthUser> bySocial(
    AuthRepository r,
    String provider,
    String s, {
    String? email,
    bool verified = true,
  }) async {
    final v = await r.loginWithSocial(
      provider: provider,
      sub: s,
      email: email,
      emailVerified: verified,
    );
    expect(v.ok, isTrue, reason: 'the $provider sign-in itself failed');
    return v.user!;
  }

  /// `PATCH /me` through the real route, as [userId], over this twin.
  ///
  /// A throw is the route's 500 (Postgres's `23505` escaping to the
  /// observability middleware), reported as such.
  Future<({int status, Map<String, dynamic> body})> patchMe(
    AuthRepository r,
    String userId,
    Map<String, Object?> body,
  ) async {
    final c = _Ctx();
    when(() => c.request).thenReturn(
      Request(
        'PATCH',
        Uri.parse('http://localhost/me'),
        headers: {
          'Authorization':
              'Bearer ${tokens.issueAccessToken(subject: userId, role: 'user').token}',
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
    when(() => c.read<TokenService>()).thenReturn(tokens);
    when(() => c.read<AuthRepository>()).thenReturn(r);
    when(
      () => c.read<UploadVerificationService>(),
    ).thenReturn(UploadVerificationService(storage: FakeStorageService()));
    final Response res;
    try {
      res = await me_route.onRequest(c);
    } on Object catch (e) {
      fail('PATCH /me threw — the route answers 500: ${e.runtimeType}');
    }
    return (
      status: res.statusCode,
      body: (await res.json() as Map).cast<String, dynamic>(),
    );
  }

  group('PATCH /me no longer changes the address (§3.2)', () {
    test('[P1] another account\'s address → 409; B still reaches B', () async {
      final r = repo();
      final aEmail = address('a');
      final a = await byCode(r, aEmail);
      final bEmail = address('b');
      final b = await byCode(r, bEmail);

      final res = await patchMe(r, a.id, {'email': bEmail});
      expect(
        res.status,
        HttpStatus.conflict,
        reason: '[P1] a different address must be refused',
      );
      expect(res.body['error'], 'email_change_requires_code');
      // A copy, not `a.email`: the in-memory twin hands out its live object.
      expect((await r.userById(a.id))!.email, aEmail, reason: '[P1] A kept');
      expect(
        (await byCode(r, bEmail)).id,
        b.id,
        reason: "[P1] B's next code sign-in must reach B",
      );
    });

    test('[P1b] the same, in upper case and with spaces → 409', () async {
      final r = repo();
      final a = await byCode(r, address('a'));
      final bEmail = address('b');
      final b = await byCode(r, bEmail);

      final res = await patchMe(r, a.id, {
        'email': '  ${bEmail.toUpperCase()} ',
      });
      expect(res.status, HttpStatus.conflict, reason: '[P1b] refused');
      expect(res.body['error'], 'email_change_requires_code');
      expect((await byCode(r, bEmail)).id, b.id, reason: '[P1b] B reaches B');
    });

    test("[P5] '' on an e-mail-code account → 409; it keeps its "
        'way in', () async {
      final r = repo();
      final email = address('p5');
      final a = await byCode(r, email);

      final res = await patchMe(r, a.id, {'email': ''});
      expect(
        res.status,
        HttpStatus.conflict,
        reason: '[P5] clearing the address must be refused',
      );
      expect(res.body['error'], 'email_change_requires_code');
      expect(
        (await byCode(r, email)).id,
        a.id,
        reason: '[P5] its next code sign-in must reach the same account',
      );
    });

    test('its own address, any case or spacing, is accepted and '
        'changes nothing', () async {
      final r = repo();
      final email = address('own');
      final a = await byCode(r, email);

      final res = await patchMe(r, a.id, {
        'email': ' ${email.toUpperCase()}  ',
        'name': 'Awa',
      });
      expect(res.status, HttpStatus.ok, reason: 'its own address, re-sent');
      expect(res.body['email'], email);
      expect(res.body['name'], 'Awa', reason: 'the rest of the save applies');
      final after = (await r.userById(a.id))!;
      expect(after.email, email);
      expect(after.emailVerified, isTrue, reason: 'still proven');
    });

    test("'' on an account without an address is accepted", () async {
      final r = repo();
      final phone = '+22507${(run % 100000000).toString().padLeft(8, '0')}';
      final code = (await r.requestOtp(phone)).devCode!;
      final p = (await r.verifyOtp(phone, code)).user!;
      expect(p.email, isNull, reason: 'a phone account holds no address');

      final res = await patchMe(r, p.id, {'email': '', 'name': 'Ama'});
      expect(res.status, HttpStatus.ok, reason: 'the app sends this on save');
      expect(res.body['name'], 'Ama');
    });
  });

  group('an address reaches an account only once proven (§5.1)', () {
    test('[P2] A (Google) holds X unproven; its owner signs in by code: '
        'a separate account, A keeps its own and no longer holds X', () async {
      final r = repo();
      final gA = sub('gA');
      final a = await bySocial(r, 'google', gA, email: address('a'));
      final x = address('x');
      await plant(r, a.id, x);

      final owner = await byCode(r, x);
      expect(
        owner.id,
        isNot(a.id),
        reason: "[P2] the owner of X must not land in A's account",
      );
      expect(owner.email, x);
      expect(owner.emailVerified, isTrue);
      expect(
        (await bySocial(r, 'google', gA)).id,
        a.id,
        reason: "[P2] A's Google sign-in still reaches A",
      );
      expect(
        (await r.userById(a.id))!.email,
        isNull,
        reason: '[P2] A no longer holds the address it never proved',
      );
    });

    test('[P3] A (Apple) holds X unproven; its owner signs in with Google: '
        'a separate account', () async {
      final r = repo();
      final apA = sub('apA');
      final a = await bySocial(r, 'apple', apA, email: address('a'));
      final x = address('x');
      await plant(r, a.id, x);

      final owner = await bySocial(r, 'google', sub('gO'), email: x);
      expect(
        owner.id,
        isNot(a.id),
        reason: "[P3] the owner of X must not land in A's account",
      );
      expect(owner.email, x);
      expect(
        (await bySocial(r, 'apple', apA)).id,
        a.id,
        reason: "[P3] A's Apple sign-in still reaches A",
      );
      expect((await r.userById(a.id))!.email, isNull, reason: '[P3] taken');
    });

    test('[same provider] A (Google g1) holds X unproven; the owner signs in '
        'with Google g2: a separate account, and g1 still reaches A', () async {
      final r = repo();
      final g1 = sub('g1');
      final a = await bySocial(r, 'google', g1, email: address('a'));
      final x = address('x');
      await plant(r, a.id, x);

      final g2 = sub('g2');
      final owner = await bySocial(r, 'google', g2, email: x);
      expect(
        owner.id,
        isNot(a.id),
        reason: "[same provider] the owner must not land in A's account",
      );
      expect(
        (await bySocial(r, 'google', g1)).id,
        a.id,
        reason:
            "[same provider] A's own Google link must be kept, not replaced",
      );
      expect(
        (await bySocial(r, 'google', g2)).id,
        owner.id,
        reason: "[same provider] the owner's sign-in reaches the owner again",
      );
    });

    test('[never relinked] B proved X with Google gB; another Google account '
        'asserting X gets an account of its own, without X', () async {
      final r = repo();
      final gB = sub('gB');
      final x = address('x');
      final b = await bySocial(r, 'google', gB, email: x);

      final g3 = sub('g3');
      final other = await bySocial(r, 'google', g3, email: x);
      expect(
        other.id,
        isNot(b.id),
        reason: "[never relinked] B's Google link must never be replaced",
      );
      expect(
        other.email,
        isNull,
        reason: '[never relinked] X stays the proven holder\'s',
      );
      expect(
        (await bySocial(r, 'google', gB)).id,
        b.id,
        reason: "[never relinked] B's own Google sign-in still reaches B",
      );
      final bAfter = (await r.userById(b.id))!;
      expect(bAfter.email, x);
      expect(bAfter.emailVerified, isTrue);
    });

    test('a proven address with an EMPTY sub for that provider links, '
        'as before', () async {
      final r = repo();
      final x = address('x');
      final b = await byCode(r, x);
      expect(
        (await bySocial(r, 'google', sub('gL'), email: x)).id,
        b.id,
        reason: 'the link rule of auth-social-email.md §4 stays',
      );
    });

    test('[by sub first] an account signing in with its own sub proves its '
        'own unproven address', () async {
      final r = repo();
      final gA = sub('gA');
      final a = await bySocial(r, 'google', gA, email: address('a'));
      final x = address('x');
      await plant(r, a.id, x);

      final again = await bySocial(r, 'google', gA, email: x);
      expect(again.id, a.id, reason: '[by sub first] by its sub');
      expect(
        again.emailVerified,
        isTrue,
        reason: '[by sub first] the sign-in\'s own answer says proven too',
      );
      final after = (await r.userById(a.id))!;
      expect(after.email, x);
      expect(
        after.emailVerified,
        isTrue,
        reason: '[by sub first] Google asserted it: proven now',
      );
    });

    test('[P4, control] no profile change: the owner of X gets an account '
        'of its own', () async {
      final r = repo();
      final a = await bySocial(r, 'google', sub('gA'), email: address('a'));
      final owner = await byCode(r, address('x'));
      expect(owner.id, isNot(a.id));
    });

    test(
      'a proven address: the next code sign-in reaches its holder',
      () async {
        final r = repo();
        final x = address('x');
        final b = await byCode(r, x);
        expect((await byCode(r, x)).id, b.id);
      },
    );
  });

  group('an unverified address is kept out (§5.1, P6)', () {
    test('[P6] H proved X; a sign-in with X UNVERIFIED gets no address, '
        'and H still reaches H', () async {
      final r = repo();
      final x = address('x');
      final h = await byCode(r, x);

      final OtpVerifyResult v;
      try {
        v = await r.loginWithSocial(
          provider: 'google',
          sub: sub('gU'),
          email: x,
        );
      } on Object catch (e) {
        fail('[P6] the sign-in threw (${e.runtimeType}): Postgres 23505');
      }
      expect(v.ok, isTrue);
      expect(v.user!.id, isNot(h.id));
      expect(
        v.user!.email,
        isNull,
        reason: '[P6] an unverified address is stored only when free',
      );
      expect(
        (await byCode(r, x)).id,
        h.id,
        reason: "[P6] H's next code sign-in must reach H",
      );
    });

    test('[P6b] H holds X unproven; an unverified sign-in with X takes '
        'nothing and gets no address', () async {
      final r = repo();
      final h = await bySocial(r, 'apple', sub('apH'), email: address('h'));
      final x = address('x');
      await plant(r, h.id, x);

      final OtpVerifyResult v;
      try {
        v = await r.loginWithSocial(
          provider: 'google',
          sub: sub('gU'),
          email: x,
        );
      } on Object catch (e) {
        fail('[P6b] the sign-in threw (${e.runtimeType}): Postgres 23505');
      }
      expect(v.user!.email, isNull, reason: '[P6b] no address');
      expect(
        (await r.userById(h.id))!.email,
        x,
        reason: '[P6b] an unverified claim takes nothing',
      );
    });

    test('an unverified address nobody holds is stored, unproven', () async {
      final r = repo();
      final x = address('x');
      final v = await r.loginWithSocial(
        provider: 'google',
        sub: sub('gF'),
        email: x,
      );
      expect(v.user!.email, x);
      expect(v.user!.emailVerified, isFalse);
    });
  });

  group('changeEmail — proven by a code (§3.1, §5.2, §5.3)', () {
    Future<String> codeFor(AuthRepository r, String email) async =>
        (await r.requestEmailOtp(email)).devCode!;
    String wrong(String code) => code == '111111' ? '222222' : '111111';

    test('a Google account changes to a free address: proven, and its '
        'next code sign-in reaches it', () async {
      final r = repo();
      final gA = sub('gA');
      final aEmail = address('a');
      final a = await bySocial(r, 'google', gA, email: aEmail);
      expect(
        await r.emailIsOnlySignIn(a.id),
        isFalse,
        reason: 'a Google link is another way in: no second code (265)',
      );
      final x = address('x');
      final res = await r.changeEmail(a.id, x, await codeFor(r, x));
      expect(res.ok, isTrue, reason: '${res.error}');
      expect(res.user!.email, x);
      expect(res.user!.emailVerified, isTrue);
      expect(res.previousEmail, aEmail, reason: 'its proven address');
      expect((await byCode(r, x)).id, a.id, reason: 'X now reaches A');
      expect((await bySocial(r, 'google', gA)).id, a.id);
    });

    test('[P1] another account proved X: email_taken, and the code is left '
        "for X's owner's sign-in", () async {
      final r = repo();
      final aEmail = address('a');
      final a = await bySocial(r, 'google', sub('gA'), email: aEmail);
      final x = address('x');
      final b = await byCode(r, x);

      final code = await codeFor(r, x);
      final res = await r.changeEmail(a.id, x, code);
      expect(res.error, 'email_taken');
      expect((await r.userById(a.id))!.email, aEmail, reason: 'A unchanged');
      final v = await r.verifyEmailOtp(x, code);
      expect(
        v.ok,
        isTrue,
        reason: '[P1] email_taken must not consume the code (§3.1)',
      );
      expect(v.user!.id, b.id, reason: '[P1] B still reaches B');
    });

    test('email_taken only once the code is right: a wrong code says '
        'nothing about the holder (decision 262)', () async {
      final r = repo();
      final a = await bySocial(r, 'google', sub('gA'), email: address('a'));
      final x = address('x');
      await byCode(r, x);
      final code = await codeFor(r, x);
      expect((await r.changeEmail(a.id, x, wrong(code))).error, 'otp_invalid');
      expect(
        (await r.changeEmail(a.id, address('nobody'), '123456')).error,
        'otp_none',
      );
    });

    test('an unproven holder loses X to the account that proves it', () async {
      final r = repo();
      final h = await bySocial(r, 'apple', sub('apH'), email: address('h'));
      final x = address('x');
      await plant(r, h.id, x);
      final a = await bySocial(r, 'google', sub('gA'), email: address('a'));

      final res = await r.changeEmail(a.id, x, await codeFor(r, x));
      expect(res.ok, isTrue, reason: '${res.error}');
      expect((await r.userById(h.id))!.email, isNull, reason: 'taken from H');
      expect((await byCode(r, x)).id, a.id);
    });

    test('its own unproven address, proven (« Vérifier »): no notice, '
        'nothing taken', () async {
      final r = repo();
      final a = await bySocial(r, 'google', sub('gA'), email: address('a'));
      final x = address('x');
      await plant(r, a.id, x);

      final res = await r.changeEmail(a.id, x, await codeFor(r, x));
      expect(res.ok, isTrue, reason: '${res.error}');
      expect(res.user!.email, x);
      expect(res.user!.emailVerified, isTrue);
      expect(res.previousEmail, isNull, reason: 'it replaced nothing proven');
    });

    test('its own proven address: email_unchanged, nothing consumed', () async {
      final r = repo();
      final x = address('x');
      final a = await byCode(r, x);
      final code = await codeFor(r, x);
      expect((await r.changeEmail(a.id, x, code)).error, 'email_unchanged');
      expect((await r.verifyEmailOtp(x, code)).user!.id, a.id);
    });

    test('the code refused: otp_invalid, then otp_locked; otp_none', () async {
      final r = repo();
      final a = await bySocial(r, 'google', sub('gA'), email: address('a'));
      final x = address('x');
      final code = await codeFor(r, x);
      var last = '';
      for (var i = 0; i < 5; i++) {
        last = (await r.changeEmail(a.id, x, wrong(code))).error!;
      }
      expect(last, 'otp_locked', reason: 'the sign-in\'s attempt budget');
      expect((await r.changeEmail(a.id, x, code)).error, 'otp_locked');
      expect(
        (await r.changeEmail(a.id, address('none'), code)).error,
        'otp_none',
      );
    });

    test('a suspended account: account_suspended; a missing one: '
        'not_found', () async {
      final r = repo();
      final a = await bySocial(r, 'google', sub('gA'), email: address('a'));
      await r.setStatus(a.id, 'banned');
      final x = address('x');
      expect(
        (await r.changeEmail(a.id, x, await codeFor(r, x))).error,
        'account_suspended',
      );
      expect(
        (await r.changeEmail('user_none', x, '123456')).error,
        'not_found',
      );
    });

    group('decision 265: its address is its only sign-in', () {
      test('the current address\'s code is required, checked, and only '
          'then are both consumed', () async {
        final r = repo();
        final current = address('cur');
        final a = await byCode(r, current);
        expect(await r.emailIsOnlySignIn(a.id), isTrue);
        final x = address('x');
        final code = await codeFor(r, x);

        expect(
          (await r.changeEmail(a.id, x, code)).error,
          'current_otp_none',
          reason: '[265] no current code',
        );
        final currentCode = await codeFor(r, current);
        expect(
          (await r.changeEmail(
            a.id,
            x,
            code,
            currentCode: wrong(currentCode),
          )).error,
          'current_otp_invalid',
        );
        // The new address's code survived both refusals.
        final res = await r.changeEmail(
          a.id,
          x,
          code,
          currentCode: currentCode,
        );
        expect(res.ok, isTrue, reason: '${res.error}');
        expect(res.previousEmail, current, reason: 'the notice goes there');
        expect(
          (await r.verifyEmailOtp(current, currentCode)).error,
          'otp_none',
          reason: 'the current code was consumed',
        );
        final again = await byCode(r, current);
        expect(
          again.id,
          isNot(a.id),
          reason: 'the old address no longer reaches A',
        );
        expect((await byCode(r, x)).id, a.id);
      });

      test('a wrong NEW code leaves the current code unconsumed', () async {
        final r = repo();
        final current = address('cur');
        final a = await byCode(r, current);
        final x = address('x');
        final code = await codeFor(r, x);
        final currentCode = await codeFor(r, current);
        expect(
          (await r.changeEmail(
            a.id,
            x,
            wrong(code),
            currentCode: currentCode,
          )).error,
          'otp_invalid',
        );
        final res = await r.changeEmail(
          a.id,
          x,
          code,
          currentCode: currentCode,
        );
        expect(res.ok, isTrue, reason: 'both codes still good: ${res.error}');
      });

      test('a phone account adding its first address needs no second '
          'code', () async {
        final r = repo();
        final phone =
            '+22501${(DateTime.now().microsecond * 997 % 100000000).toString().padLeft(8, '0')}';
        final p = (await r.verifyOtp(
          phone,
          (await r.requestOtp(phone)).devCode!,
        )).user!;
        expect(await r.emailIsOnlySignIn(p.id), isFalse);
        final x = address('x');
        final res = await r.changeEmail(p.id, x, await codeFor(r, x));
        expect(res.ok, isTrue, reason: '${res.error}');
        expect(res.previousEmail, isNull);
      });
    });
  });
}
