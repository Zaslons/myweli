import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/session_ended_notice.dart';

import '../support/dart_source.dart';

/// consumer-signin-push.md §8, source guards. Each was watched red once.
///
/// The defect they hold back: every way into the sign-in used `go`, which
/// REPLACES the screen stack — a guest who tapped a heart met a screen with
/// no way out (audit gap 10). Since A3 one helper, `openSignIn`, pushes it
/// over the screen the person is on.
void main() {
  /// The client app's code: `lib/` minus MyWeli Pro's screens and stores,
  /// which have their own sign-in (`/pro/login`) and none of this rule.
  bool isPro(String path) =>
      path.contains('/screens/provider/') ||
      path.split('/').last.startsWith('pro_');

  Map<String, String> clientSources() => {
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !isPro(f.path)))
      f.path: stripDartComments(f.readAsStringSync()),
  };

  test('no client file names the sign-in route but the helper, the router '
      'and the notice — so none can `go` there', () {
    // A quote right before « /login »: a path literal ('/login', "/login?…").
    // « /pro/login » is MyWeli Pro's, and its quote is before « /pro ».
    final literal = RegExp(r'''['"]/login''');
    final found = [
      for (final e in clientSources().entries)
        if (literal.hasMatch(e.value)) e.key,
    ]..sort();
    expect(found, [
      'lib/core/auth/open_sign_in.dart', // the push
      'lib/core/router/app_router.dart', // the route
      'lib/widgets/common/session_ended_notice.dart', // « already on it »
    ]);
  });

  test('the helper pushes; it never goes', () {
    final helper = clientSources()['lib/core/auth/open_sign_in.dart']!;
    expect(helper, contains('router'));
    expect(helper, contains('.push<Object?>('));
    expect(RegExp(r'\.go\(').hasMatch(helper), isFalse);
  });

  test('the account-only screens are exactly the four of §2.7 — the ones '
      'that draw a signed-out state are not among them', () {
    expect(kAccountOnlyRoutePrefixes, [
      '/appointment/',
      '/booking/confirm',
      '/profile/notifications',
      '/profile/data',
    ]);
    for (final drawsItsOwn in [
      '/bookings',
      '/notifications',
      '/profile',
      '/profile/edit',
    ]) {
      expect(isAccountOnlyRoute(drawsItsOwn), isFalse, reason: drawsItsOwn);
    }
  });

  test('a notification tap never lands on top of an open sign-in: main.dart '
      'waits for it to close, and replays only once it has (§2.2)', () {
    final main = stripDartComments(File('lib/main.dart').readAsStringSync());
    final start = main.indexOf('PushMessageHandler(');
    expect(start, isNot(-1));
    final wiring = main.substring(
      start,
      main.indexOf('FcmMessageBridge', start),
    );
    final navigate = wiring.substring(
      wiring.indexOf('navigate:'),
      wiring.indexOf('allowedRoutePrefixes'),
    );
    expect(navigate, contains('await SignInGate.whenClosed()'));
    expect(
      navigate.indexOf('whenClosed'),
      lessThan(navigate.indexOf('.push')),
      reason: 'it waits BEFORE it pushes',
    );
    expect(wiring, contains('!SignInGate.isOpen.value'));
    expect(wiring, contains('SignInGate.isOpen.addListener('));
  });

  test('each push ask stays with its app: the client offers after a booking, '
      'MyWeli Pro asks once on its dashboard', () {
    final all = {
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        f.path: stripDartComments(f.readAsStringSync()),
    };
    const home = 'lib/core/push/push_registration.dart';
    final askOnce = [
      for (final e in all.entries)
        if (e.key != home && e.value.contains('maybePromptOnce(')) e.key,
    ];
    final offer = [
      for (final e in all.entries)
        if (e.key != home && e.value.contains('maybeOfferAfterBooking(')) e.key,
    ];
    expect(askOnce, ['lib/screens/provider/dashboard/dashboard_screen.dart']);
    expect(offer, ['lib/screens/booking/booking_confirmation_screen.dart']);
  });
}
