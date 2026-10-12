import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_splash_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../support/pro_splash.dart';
import '../support/pump_app.dart';

/// The Pro splash (docs/design/pro-open-animation.md): the « MyWeli Pro »
/// open animation, and a route decided only once BOTH the intro has played
/// and the session has loaded — run side by side, not one after the other.
void main() {
  final timeline = ProOpenTimeline.load();
  const justUnder = Duration(milliseconds: 100);

  // `serviceLocator.authService` is a late final: set once per test file.
  final counting = _CountingAuth();
  setUpAll(() => serviceLocator.authService = counting);

  Future<void> pumpSplash(
    WidgetTester tester,
    ProAuthProvider session, {
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

  testWidgets('starts no session load of its own — it awaits the one running', (
    tester,
  ) async {
    final session = FakeProSession(signedIn: true);
    final before = session.loadCalls;
    await pumpSplash(tester, session);
    session.load.complete();
    await playIntro(tester);

    expect(find.text('route:dashboard'), findsOneWidget);
    expect(
      session.loadCalls,
      before,
      reason:
          'the constructor already started the load: a second one '
          'repeats every authenticated request at cold start',
    );
  });

  testWidgets('a load that finished before the first frame is not run again', (
    tester,
  ) async {
    // main_pro.dart builds the provider, then awaits the version gate (up to
    // 1.5 s) before `runApp` — so a fast load is over before the splash exists.
    // Built in the test's own (fake) zone: a future completed under
    // `runAsync` would hand its callbacks to the real event loop, which the
    // pumps below never turn.
    final auth = ProAuthProvider();
    var loaded = false;
    unawaited(auth.ready.then((_) => loaded = true));
    await tester.pump(const Duration(seconds: 1));
    expect(loaded, isTrue, reason: 'the premise: done before the first frame');
    final reads = counting.currentProviderReads;
    expect(reads, greaterThan(0), reason: 'the constructor read the session');

    await pumpSplash(tester, auth);
    await playIntro(tester);

    expect(find.text('route:login'), findsOneWidget);
    expect(
      counting.currentProviderReads,
      reads,
      reason: 'the splash must not restore the session a second time',
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

  group('the bounded wait (live refresh after the stored session)', () {
    testWidgets(
      'a refresh that hangs → routes at the deadline, on the stored session',
      (tester) async {
        // Read from storage: a signed-in Collaborateur. The live refresh never
        // answers — a captive portal.
        final session = FakeProSession(signedIn: true, staff: true)
          ..restore.complete();
        await pumpSplash(tester, session);
        await tester.pump(timeline.intro);

        await tester.pump(ProSplashScreen.sessionDeadline - justUnder);
        expect(
          find.text('route:staff', skipOffstage: false),
          findsNothing,
          reason: 'the refresh is owed its deadline after the intro',
        );

        await tester.pump(justUnder * 2);
        await land(tester);
        expect(find.text('route:staff'), findsOneWidget);
        expect(
          session.load.isCompleted,
          isFalse,
          reason: 'the refresh is left running, not abandoned',
        );
        expect(session.loadCalls, 1, reason: 'and not restarted');
      },
    );

    testWidgets('a refresh that lands inside the window → routes at once', (
      tester,
    ) async {
      final session = FakeProSession(signedIn: true)..restore.complete();
      await pumpSplash(tester, session);
      await tester.pump(timeline.intro);
      await tester.pump(justUnder);
      expect(find.text('route:dashboard', skipOffstage: false), findsNothing);

      session.load.complete();
      await land(tester);
      expect(
        find.text('route:dashboard'),
        findsOneWidget,
        reason: 'well before the deadline — it is a bound, not a delay',
      );
    });

    testWidgets('the stored session itself is waited for — no route guessed', (
      tester,
    ) async {
      final session = FakeProSession(signedIn: true);
      await pumpSplash(tester, session);
      await tester.pump(timeline.intro + ProSplashScreen.sessionDeadline * 3);
      expect(
        find.text('route:login', skipOffstage: false),
        findsNothing,
        reason: 'without the stored session there is no right answer',
      );

      session.restore.complete();
      await tester.pump(ProSplashScreen.sessionDeadline);
      await land(tester);
      expect(find.text('route:dashboard'), findsOneWidget);
    });
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
    expect(
      find.byType(SvgPicture),
      findsOneWidget,
      reason: 'the still brand mark stands in for the animation',
    );
    expect(
      find.text(BrandLoader.semanticsLabel),
      findsOneWidget,
      reason: 'a still mark while the session loads must say so',
    );

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

/// Counts how often the stored session is read.
class _CountingAuth extends MockAuthService {
  int currentProviderReads = 0;

  @override
  Future<ProviderUser?> getCurrentProvider() {
    currentProviderReads++;
    return super.getCurrentProvider();
  }
}
