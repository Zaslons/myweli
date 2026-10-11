import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_splash_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:provider/provider.dart';

import '../support/pro_splash.dart';
import '../support/pump_app.dart';

/// The Pro splash (docs/design/pro-open-animation.md): the « MyWeli Pro »
/// open animation, and a route decided only once BOTH the intro has played
/// and the session has loaded — run side by side, not one after the other.
void main() {
  final timeline = ProOpenTimeline.load();
  const justUnder = Duration(milliseconds: 100);

  setUpAll(() => serviceLocator.authService = MockAuthService());

  Future<void> pumpSplash(
    WidgetTester tester,
    FakeProSession session, {
    AssetBundle? bundle,
  }) async {
    Widget app = wrapApp(
      routerConfig: proSplashRouter(),
      providers: [
        ChangeNotifierProvider<ProAuthProvider>.value(value: session),
      ],
    );
    if (bundle != null) app = DefaultAssetBundle(bundle: bundle, child: app);
    await tester.pumpWidget(app);
    // The composition is decoded off a real bundle read; until it lands there
    // is no intro to time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }

  double controllerValue(WidgetTester tester) => tester
      .widget<LottieBuilder>(find.byType(LottieBuilder))
      .controller!
      .value;

  /// A `go` lands over a few frames: the gate's futures resolve, the router
  /// rebuilds, and the hero controller holds a pushed page offstage for one.
  Future<void> land(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  Future<void> playIntro(WidgetTester tester) async {
    await tester.pump(timeline.intro);
    await land(tester);
  }

  group('routing decision (unchanged)', () {
    for (final (label, signedIn, staff, route) in [
      ('signed-in owner', true, false, 'dashboard'),
      ('signed-in staff', true, true, 'staff'),
      ('signed out', false, false, 'login'),
    ]) {
      testWidgets('$label → /pro/$route', (tester) async {
        final session = FakeProSession(signedIn: signedIn, staff: staff)
          ..load.complete();
        await pumpSplash(tester, session);
        await playIntro(tester);
        expect(find.text('route:$route'), findsOneWidget);
      });
    }
  });

  testWidgets('starts the session load at once, beside the intro', (
    tester,
  ) async {
    final session = FakeProSession();
    final before = session.loadCalls;
    await pumpSplash(tester, session);
    expect(
      session.loadCalls,
      before + 1,
      reason: 'the load must not be chained behind a delay or the intro',
    );
  });

  testWidgets('session first → still waits for the intro to finish', (
    tester,
  ) async {
    final session = FakeProSession(signedIn: true)..load.complete();
    await pumpSplash(tester, session);

    await tester.pump(timeline.intro - justUnder);
    expect(find.byType(ProSplashScreen), findsOneWidget);
    expect(
      find.text('route:dashboard', skipOffstage: false),
      findsNothing,
      reason: 'not even a page building offstage',
    );

    await tester.pump(justUnder * 2);
    await land(tester);
    expect(find.text('route:dashboard'), findsOneWidget);
  });

  testWidgets('intro first → loops the mark redraw until the session lands', (
    tester,
  ) async {
    final session = FakeProSession(signedIn: true);
    await pumpSplash(tester, session);
    await playIntro(tester);

    // Two full loops and change, sampled: always inside the redraw segment —
    // the wordmark (before `loop`) is never replayed.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        timeline.frameOf(controllerValue(tester)),
        greaterThanOrEqualTo(timeline.loopStartFrame - 0.05),
        reason: 'sample $i replayed the intro',
      );
      expect(
        find.text('route:dashboard', skipOffstage: false),
        findsNothing,
        reason: 'not even a page building offstage',
      );
    }
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'still looping');

    session.load.complete();
    await land(tester);
    expect(find.text('route:dashboard'), findsOneWidget);
  });

  testWidgets('a screen reader hears « MyWeli Pro »', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSplash(tester, FakeProSession());
    expect(
      find.bySemanticsLabel(ProSplashScreen.semanticsLabel),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('an asset that will not load never strands the user', (
    tester,
  ) async {
    // The cache keys on the asset name, not the bundle that served it: a
    // composition an earlier test decoded would be handed straight back.
    Lottie.cache.clear();
    final session = FakeProSession();
    await pumpSplash(tester, session, bundle: _MissingAssetBundle());
    await tester.pump();
    expect(find.text(ProSplashScreen.semanticsLabel), findsOneWidget);

    session.load.complete();
    await land(tester);
    expect(
      find.text('route:login'),
      findsOneWidget,
      reason: 'no intro to wait for — the session is the only gate left',
    );
  });
}

/// A bundle where the Pro animation is missing — a broken build.
class _MissingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == ProSplashScreen.asset) throw FlutterError('missing: $key');
    return rootBundle.load(key);
  }
}
