import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/landed_push_handler.dart';
import 'package:myweli/core/push/push_message_handler.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_splash_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:provider/provider.dart';

import '../support/pro_splash.dart';
import '../support/pump_app.dart';

/// A notification tap that LAUNCHES the Pro app must open its page — not be
/// eaten by the `go` the splash (or the sign-in screen) hands over with
/// (docs/design/pro-open-animation.md §2.6, push-notifications-app.md §10.4).
///
/// The sequence is main_pro.dart's, in order: `getInitialMessage` delivers
/// the tap before `runApp`; the session load signs in while the intro is
/// still playing; the splash routes with `context.go`. The replay used to
/// fire at the sign-in — above the splash — and the `go` replaced it.
void main() {
  final timeline = ProOpenTimeline.load();
  const tap = <String, Object?>{
    'route': '/pro/appointment/a1?salon=s1',
    'providerId': 's1',
  };

  setUpAll(() => serviceLocator.authService = MockAuthService());

  /// The handler exactly as `_startPush` wires it, on the test router.
  PushMessageHandler wire(GoRouter router, FakeProSession session) =>
      landedPushHandler(
        router: router,
        session: session,
        isSignedIn: () => session.isAuthenticated,
        launchPaths: ProRouter.launchPaths,
        allowedRoutePrefixes: kProRoutePrefixes,
        ensureSalon: session.switchSalon,
        salonSwitchFallbackRoute: '/pro/dashboard',
      );

  Future<void> launch(
    WidgetTester tester,
    GoRouter router,
    ProAuthProvider session,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        routerConfig: router,
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: session),
        ],
      ),
    );
    // The composition is decoded off a real bundle read.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }

  /// A navigation lands over a few frames (and a page transition).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  final appointment = find.text('route:appointment a1', skipOffstage: false);

  testWidgets('signed in: the tapped booking opens above the dashboard', (
    tester,
  ) async {
    final session = FakeProSession();
    final router = proSplashRouter();
    final handler = wire(router, session);

    // 1. Before `runApp`: the tap that launched the app.
    await handler.handleData(tap);
    // 2. `runApp` — the splash and its intro.
    await launch(tester, router, session);
    // 3. The stored session signs in mid-intro: where the replay used to run.
    session.signIn();
    session.load.complete();
    await tester.pump();
    await tester.pump();
    expect(
      appointment,
      findsNothing,
      reason: 'pushed above the splash, it would be replaced by its go',
    );

    // 4. The intro ends; the splash routes; the tap replays on top.
    await tester.pump(timeline.intro);
    await settle(tester);
    expect(find.text('route:appointment a1'), findsOneWidget);
    expect(session.switchedTo, ['s1'], reason: 'the salon switch replays too');

    // …with the dashboard beneath it, so « retour » is not a dead end.
    router.pop();
    await settle(tester);
    expect(find.text('route:dashboard'), findsOneWidget);
  });

  testWidgets('signed out: it waits through the login and opens after it', (
    tester,
  ) async {
    final session = FakeProSession()..load.complete();
    final router = proSplashRouter();
    final handler = wire(router, session);

    await handler.handleData(tap);
    await launch(tester, router, session);
    await tester.pump(timeline.intro);
    await settle(tester);
    expect(find.text('route:login'), findsOneWidget);

    // The login signs in — and notifies — BEFORE the screen's own `go`.
    session.signIn();
    await settle(tester);
    expect(
      appointment,
      findsNothing,
      reason: 'the login screen is about to go, which would replace it',
    );

    router.go('/pro/dashboard'); // what ProLoginScreen._finish does
    await settle(tester);
    expect(find.text('route:appointment a1'), findsOneWidget);
  });

  testWidgets('a tap once the app is in use still opens at once', (
    tester,
  ) async {
    final session = FakeProSession(signedIn: true)..load.complete();
    final router = proSplashRouter();
    final handler = wire(router, session);

    await launch(tester, router, session);
    await tester.pump(timeline.intro);
    await settle(tester);
    expect(find.text('route:dashboard'), findsOneWidget);

    var handled = false;
    unawaited(handler.handleData(tap).then((_) => handled = true));
    await settle(tester);
    expect(find.text('route:appointment a1'), findsOneWidget);
    expect(
      handled,
      isTrue,
      reason:
          'handling a tap must not wait for its page to be popped — '
          'main_pro.dart awaits the launch tap\'s handling before runApp',
    );
  });

  testWidgets('a tap before runApp on an already-restored session waits too', (
    tester,
  ) async {
    // `getInitialMessage` can answer after the stored session is read: signed
    // in, but no router mounted yet — nothing to push onto.
    final session = FakeProSession(signedIn: true);
    final router = proSplashRouter();
    final handler = wire(router, session);

    var handled = false;
    unawaited(handler.handleData(tap).then((_) => handled = true));
    await tester.pump();
    expect(handled, isTrue, reason: 'buffered at once — runApp is waiting');

    await launch(tester, router, session);
    expect(find.byType(ProSplashScreen), findsOneWidget);
    expect(appointment, findsNothing);

    session.load.complete();
    await tester.pump(timeline.intro);
    await settle(tester);
    expect(find.text('route:appointment a1'), findsOneWidget);
    router.pop();
    await settle(tester);
    expect(find.text('route:dashboard'), findsOneWidget);
  });
}
