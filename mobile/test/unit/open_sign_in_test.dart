import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/auth/open_sign_in.dart';

/// consumer-signin-push.md §2.1–§2.2: the reason lines, where a sign-in with
/// nothing beneath may go, and the gate every opener waits on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(SignInGate.reset);

  group('SignInReason', () {
    test('every reason has its line; the session one is the notice\'s', () {
      expect(
        SignInReason.none.line,
        'Connectez-vous pour réserver en quelques secondes.',
      );
      expect(
        SignInReason.heart.line,
        'Connectez-vous pour ajouter ce salon à vos favoris.',
      );
      expect(
        SignInReason.booking.line,
        'Connectez-vous pour confirmer votre réservation.',
      );
      expect(
        SignInReason.bookings.line,
        'Connectez-vous pour retrouver vos rendez-vous.',
      );
      expect(
        SignInReason.actu.line,
        'Connectez-vous pour suivre vos rendez-vous et les réponses des '
        'salons.',
      );
      expect(
        SignInReason.profile.line,
        'Connectez-vous pour modifier votre profil.',
      );
      expect(
        SignInReason.sessionEnded.line,
        'Votre session a expiré. Reconnectez-vous.',
      );
      // Every line names an action: none is blank or duplicated.
      final lines = SignInReason.values.map((r) => r.line).toSet();
      expect(lines.length, SignInReason.values.length);
    });

    test('a key reads back as its reason; an unknown or missing one is none', () {
      for (final r in SignInReason.values) {
        expect(SignInReason.fromKey(r.name), r);
      }
      expect(SignInReason.fromKey('nope'), SignInReason.none);
      expect(SignInReason.fromKey(null), SignInReason.none);
      expect(SignInReason.fromKey(''), SignInReason.none);
    });
  });

  group('safeReturnTo (§6)', () {
    test('an in-app path is kept', () {
      expect(safeReturnTo('/bookings'), '/bookings');
      expect(safeReturnTo('/appointment/a1?x=1'), '/appointment/a1?x=1');
    });

    test('anything else lands on Accueil', () {
      for (final bad in [
        null,
        '',
        '   ',
        '//evil.example/x',
        'https://evil.example/',
        'bookings',
        'javascript:alert(1)',
      ]) {
        expect(safeReturnTo(bad), '/home', reason: '$bad');
      }
    });
  });

  group('SignInGate', () {
    test('only the first answer counts', () async {
      final router = _router();
      final opened = openSignIn(router);
      expect(SignInGate.isOpen.value, isTrue);
      SignInGate.answer(true);
      SignInGate.answer(false);
      expect(await opened, isTrue);
      expect(SignInGate.isOpen.value, isFalse);
    });

    test('a second call while one is open is ignored and answers false', () async {
      final router = _router();
      final first = openSignIn(router);
      expect(await openSignIn(router), isFalse);
      SignInGate.answer(true);
      expect(await first, isTrue);
    });

    test('the flag never sticks: closed after an answer, open again later', () async {
      final router = _router();
      final first = openSignIn(router);
      SignInGate.answer(false);
      await first;
      expect(SignInGate.isOpen.value, isFalse);
      final second = openSignIn(router);
      expect(SignInGate.isOpen.value, isTrue);
      SignInGate.answer(true);
      expect(await second, isTrue);
    });

    test('whenClosed waits for an open sign-in, and not for a closed one', () async {
      await SignInGate.whenClosed(); // none open: at once
      final router = _router();
      final opened = openSignIn(router);
      var closed = false;
      final waiting = SignInGate.whenClosed().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      SignInGate.answer(false);
      await opened;
      await waiting;
      expect(closed, isTrue);
    });
  });
}

/// Not mounted: `push` is recorded and never answers — the gate's answer is
/// the screen's, here the test's.
GoRouter _router() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SizedBox()),
    GoRoute(path: '/login', builder: (_, _) => const SizedBox()),
  ],
);
