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
import 'package:myweli/screens/splash/open_animation_player.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../support/pro_splash.dart';
import '../support/pump_app.dart';

/// The Pro splash (docs/design/pro-open-animation.md): the « MyWeli Pro »
/// open animation played through ONCE — wordmark, morph, the spin — and held
/// on the finished mark for a rest before anything may route (§2.2); the
/// session load runs underneath, and a pending one keeps the mark spinning
/// and leaves only at a spin's end (§2.3).
void main() {
  final timeline = OpenTimeline.pro();
  const justUnder = Duration(milliseconds: 100);
  const rest = OpenAnimationPlayer.rest;

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
    // is nothing to play.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await pumpFirstFrame(tester);
  }

  AnimationController controllerOf(WidgetTester tester) =>
      tester.widget<LottieBuilder>(find.byType(LottieBuilder)).controller!
          as AnimationController;

  double frameOnScreen(WidgetTester tester) =>
      timeline.frameOf(controllerOf(tester).value);

  /// A `go` lands over a few frames: the gate's futures resolve, the router
  /// rebuilds, and the hero controller holds a pushed page offstage for one.
  Future<void> land(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  /// The first pass played out — its end frame drawn — then its rest: the
  /// gate opens here.
  Future<void> throughTheGate(WidgetTester tester) async {
    await tester.pump(timeline.firstPass + OpenTimeline.frame);
    await tester.pump(rest);
  }

  Finder routed(String route) => find.text('route:$route', skipOffstage: false);

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
        await throughTheGate(tester);
        await land(tester);
        expect(find.text('route:$route'), findsOneWidget);
      });
    }

    // docs/design/pro-rejoin-gate.md S9: a former member re-invited, opening
    // the app. The session is signed in, so the branch above would send them
    // to a dashboard they no longer have.
    for (final staff in [false, true]) {
      testWidgets('the rejoin gate holding the session → /pro/invitations '
          '(staff: $staff)', (tester) async {
        final session = FakeProSession(signedIn: true, staff: staff)
          ..rejoin = true
          ..load.complete();
        await pumpSplash(tester, session);
        await throughTheGate(tester);
        await land(tester);
        expect(find.text('route:invitations'), findsOneWidget);
        expect(routed(staff ? 'staff' : 'dashboard'), findsNothing);
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
    await throughTheGate(tester);
    await land(tester);

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
    await throughTheGate(tester);
    await land(tester);

    expect(find.text('route:login'), findsOneWidget);
    expect(
      counting.currentProviderReads,
      reads,
      reason: 'the splash must not restore the session a second time',
    );
  });

  group('the whole first pass, then a rest on the finished mark', () {
    testWidgets(
      'session first → the spin plays, the mark rests, THEN it goes',
      (tester) async {
        final session = FakeProSession(signedIn: true)..load.complete();
        await pumpSplash(tester, session);

        // Past the old gate (the `intro` marker), the mark is mid-spin — the
        // part build 560 never showed.
        await tester.pump(timeline.intro + const Duration(seconds: 1));
        expect(
          frameOnScreen(tester),
          allOf(
            greaterThan(timeline.loopStartFrame),
            lessThan(timeline.endFrame),
          ),
          reason: 'mid-spin: the mark erasing or redrawing',
        );
        expect(
          routed('dashboard'),
          findsNothing,
          reason: 'the intro is not the gate any more — the spin is still on',
        );

        // A hair before the end frame: still drawing.
        await tester.pump(
          timeline.firstPass -
              timeline.intro -
              const Duration(seconds: 1) -
              justUnder,
        );
        expect(controllerOf(tester).isAnimating, isTrue);
        expect(routed('dashboard'), findsNothing);

        // The end frame is drawn — and the screen STOPS there.
        await tester.pump(justUnder + OpenTimeline.frame);
        expect(frameOnScreen(tester), closeTo(timeline.endFrame, 0.01));
        expect(
          controllerOf(tester).isAnimating,
          isFalse,
          reason: 'stopped on the finished mark — no loop restarted',
        );
        expect(
          tester.binding.hasScheduledFrame,
          isFalse,
          reason: 'nothing ticking: the mark is held, not repeated',
        );
        expect(
          routed('dashboard'),
          findsNothing,
          reason: 'not even a page building offstage',
        );

        // The rest: the finished mark held still, long enough to be SEEN — a
        // floor written here, not read from the constant, so a rest tuned
        // down to nothing fails (build 560: « on ne voit pas la fin »).
        const seen = Duration(milliseconds: 400);
        await tester.pump(seen);
        expect(routed('dashboard'), findsNothing, reason: 'still resting');
        expect(frameOnScreen(tester), closeTo(timeline.endFrame, 0.01));

        await tester.pump(rest - seen + justUnder);
        await land(tester);
        expect(find.text('route:dashboard'), findsOneWidget);
      },
    );

    testWidgets(
      'the clock is the ticker: no frames drawn, no gate — whatever the wall says',
      (tester) async {
        final session = FakeProSession(signedIn: true)..load.complete();
        await pumpSplash(tester, session);

        // The wall clock runs through the whole first pass and its rest, and
        // more — but no frame is drawn: a cold start's slow first frames, an
        // app sent to the background mid-splash. A timer beside the animation
        // would route here, on a mark nobody saw drawn.
        await tester.binding.delayed(
          timeline.firstPass + rest + const Duration(seconds: 2),
        );

        // Frames again. A route decided during the dark spell would build
        // its page on this very frame.
        await tester.pump();
        expect(
          routed('dashboard'),
          findsNothing,
          reason: 'the gate opened without a single frame of the pass',
        );
        // The ticker catches up to the end frame at once — and the rest is
        // still owed, counted from the frame that drew it.
        expect(frameOnScreen(tester), closeTo(timeline.endFrame, 0.01));

        await tester.pump(rest + justUnder);
        await land(tester);
        expect(find.text('route:dashboard'), findsOneWidget);
      },
    );
  });

  group('pending at the gate → the mark keeps spinning', () {
    testWidgets('spins from `loop` — never the wordmark again — and waits', (
      tester,
    ) async {
      final session = FakeProSession(signedIn: true);
      await pumpSplash(tester, session);
      await throughTheGate(tester);

      // Two spins and their rests, and change, sampled: always the spin or
      // the finished mark — the wordmark (before `loop`) is never replayed.
      var sawSpinning = false;
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 450));
        expect(
          frameOnScreen(tester),
          greaterThanOrEqualTo(timeline.loopStartFrame - 0.05),
          reason: 'sample $i replayed the intro',
        );
        sawSpinning |= controllerOf(tester).isAnimating;
        expect(
          routed('dashboard'),
          findsNothing,
          reason: 'not even a page building offstage',
        );
      }
      expect(sawSpinning, isTrue, reason: 'the spin repeats while pending');
    });

    testWidgets(
      'a session that lands mid-spin → leaves at that spin\'s end, on the mark',
      (tester) async {
        final session = FakeProSession(signedIn: true);
        await pumpSplash(tester, session);
        await throughTheGate(tester);

        await tester.pump(const Duration(seconds: 1));
        expect(controllerOf(tester).isAnimating, isTrue, reason: 'mid-spin');
        session.load.complete();
        await land(tester);
        expect(
          routed('dashboard'),
          findsNothing,
          reason: 'never mid-spin: the user leaves on the finished mark',
        );

        // The spin's end frame, then its rest.
        await tester.pump(
          timeline.spin - const Duration(seconds: 1) + OpenTimeline.frame,
        );
        expect(frameOnScreen(tester), closeTo(timeline.endFrame, 0.01));
        expect(controllerOf(tester).isAnimating, isFalse);
        expect(routed('dashboard'), findsNothing, reason: 'the rest is owed');

        await tester.pump(rest);
        await land(tester);
        expect(find.text('route:dashboard'), findsOneWidget);
      },
    );
  });

  group('the bounded wait (live refresh after the stored session)', () {
    testWidgets(
      'a refresh that hangs → leaves at the first spin\'s end past the '
      'deadline, on the stored session',
      (tester) async {
        // Read from storage: a signed-in Collaborateur. The live refresh never
        // answers — a captive portal.
        final session = FakeProSession(signedIn: true, staff: true)
          ..restore.complete();
        await pumpSplash(tester, session);
        await throughTheGate(tester);

        await tester.pump(ProSplashScreen.sessionDeadline - justUnder);
        expect(
          routed('staff'),
          findsNothing,
          reason: 'the refresh is owed its deadline after the gate',
        );

        // Past the deadline — mid-spin. Allowed to leave, but not here.
        await tester.pump(justUnder * 2);
        await land(tester);
        expect(controllerOf(tester).isAnimating, isTrue);
        expect(
          routed('staff'),
          findsNothing,
          reason: 'past the deadline, the screen still leaves on the mark',
        );

        await tester.pump(
          timeline.spin -
              ProSplashScreen.sessionDeadline -
              justUnder +
              OpenTimeline.frame,
        );
        expect(frameOnScreen(tester), closeTo(timeline.endFrame, 0.01));
        await tester.pump(rest);
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

    testWidgets('the stored session itself is waited for — no route guessed', (
      tester,
    ) async {
      final session = FakeProSession(signedIn: true);
      await pumpSplash(tester, session);
      await throughTheGate(tester);

      // Three spins with nothing read: it spins on.
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.byType(ProSplashScreen), findsOneWidget);
      for (final route in ['login', 'dashboard', 'staff']) {
        expect(
          routed(route),
          findsNothing,
          reason: 'without the stored session there is no right answer',
        );
      }

      // Read now: the deadline starts here, and the screen leaves at the
      // first spin's end after it — within one deadline, a spin and a rest.
      session.restore.complete();
      // (+ a margin for the 50 ms steps: the spin's end frame and the next
      // spin's first tick each land on a step.)
      final bound =
          ProSplashScreen.sessionDeadline +
          timeline.spin +
          rest +
          justUnder * 3;
      var waited = Duration.zero;
      while (routed('dashboard').evaluate().isEmpty && waited < bound) {
        await tester.pump(const Duration(milliseconds: 50));
        waited += const Duration(milliseconds: 50);
      }
      await land(tester);
      expect(find.text('route:dashboard'), findsOneWidget);
      expect(
        waited,
        greaterThanOrEqualTo(ProSplashScreen.sessionDeadline),
        reason: 'the refresh is owed its deadline after the restore',
      );
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
      reason: 'no pass to wait for — the session is the only gate left',
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
