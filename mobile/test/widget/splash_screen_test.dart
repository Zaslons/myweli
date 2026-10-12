import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:myweli/screens/splash/open_animation_player.dart';
import 'package:myweli/screens/splash/splash_screen.dart';

import '../support/open_timeline.dart';
import '../support/pump_app.dart';

/// The consumer splash (docs/design/pro-open-animation.md §2.8): the whole
/// « MyWeli » open animation once — wordmark, morph, the spin — then a rest on
/// the finished mark, stopped there, then `/home`. It used to hold a fixed
/// 3800 ms and leave at frame ≤ 95, on a mostly erased mark.
void main() {
  final timeline = OpenTimeline.consumer();
  const justUnder = Duration(milliseconds: 100);
  const rest = OpenAnimationPlayer.rest;

  GoRouter router() => GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('accueil')),
      ),
      // What a cold-start notification tap opens (§11).
      GoRoute(
        path: '/booking',
        builder: (_, _) => const Scaffold(body: Text('réservation')),
      ),
    ],
  );

  /// Returns the router, for the tests that push over the splash.
  Future<GoRouter> pumpSplash(
    WidgetTester tester, {
    AssetBundle? bundle,
  }) async {
    final routes = router();
    Widget app = wrapApp(routerConfig: routes);
    if (bundle != null) app = DefaultAssetBundle(bundle: bundle, child: app);
    await tester.pumpWidget(app);
    // The composition is decoded off a real bundle read.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await pumpFirstFrame(tester);
    return routes;
  }

  AnimationController controllerOf(WidgetTester tester) =>
      tester.widget<LottieBuilder>(find.byType(LottieBuilder)).controller!
          as AnimationController;

  double frameOnScreen(WidgetTester tester) =>
      timeline.frameOf(controllerOf(tester).value);

  final home = find.text('accueil', skipOffstage: false);

  Future<void> land(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  testWidgets('plays the whole file, rests on the finished mark, then home', (
    tester,
  ) async {
    await pumpSplash(tester);

    // Where the old 3800 ms hold left: the mark mid-erase. Still here.
    await tester.pump(const Duration(milliseconds: 3900));
    expect(
      home,
      findsNothing,
      reason: 'the fixed 3800 ms hold is gone — the spin is still playing',
    );
    expect(
      frameOnScreen(tester),
      allOf(greaterThan(timeline.loopStartFrame), lessThan(timeline.endFrame)),
      reason: 'mid-spin',
    );

    // A hair before the end frame: still drawing.
    await tester.pump(
      timeline.firstPass - const Duration(milliseconds: 3900) - justUnder,
    );
    expect(controllerOf(tester).isAnimating, isTrue);
    expect(home, findsNothing);

    // The end frame is drawn — and the screen STOPS there: no repeat.
    await tester.pump(justUnder + OpenTimeline.frame);
    expect(frameOnScreen(tester), closeTo(timeline.endFrame, 0.01));
    expect(
      controllerOf(tester).isAnimating,
      isFalse,
      reason: 'stopped on the finished mark — it used to `repeat`',
    );
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'nothing ticking while the mark rests',
    );

    // Long enough to be SEEN — a floor written here, not read from the
    // constant, so a rest tuned down to nothing fails.
    const seen = Duration(milliseconds: 400);
    await tester.pump(seen);
    expect(home, findsNothing, reason: 'the finished mark is still resting');

    await tester.pump(rest - seen + justUnder);
    await land(tester);
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('the clock is the ticker: no frames drawn, no home', (
    tester,
  ) async {
    await pumpSplash(tester);
    // The wall clock runs past the whole pass and its rest with no frame
    // drawn — a slow cold start, the app in the background.
    await tester.binding.delayed(
      timeline.firstPass + rest + const Duration(seconds: 2),
    );
    await tester.pump();
    expect(
      home,
      findsNothing,
      reason: 'a wall-clock hold would have gone home on an unseen mark',
    );
    expect(frameOnScreen(tester), closeTo(timeline.endFrame, 0.01));

    await tester.pump(rest + justUnder);
    await land(tester);
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('covered by a page, the pass freezes: no /home under it — '
      'uncovered, the end frame, the rest, then /home', (tester) async {
    // §2.2, §11 — measured, then pinned. A page pushed over the splash (the
    // consumer's cold-start tap replays with a `push` while the first pass
    // plays) puts it offstage, built under `TickerMode(enabled: false)`: its
    // ticker is muted and the pass stops. With motion on, the splash does
    // NOT `go` under the page — unlike reduced motion and the rest, which run
    // on timers (§11). The follow-up starts from this, not from a reading.
    final routes = await pumpSplash(tester);
    final booking = find.text('réservation', skipOffstage: false);
    AnimationController covered() =>
        tester
                .widget<LottieBuilder>(
                  find.byType(LottieBuilder, skipOffstage: false),
                )
                .controller!
            as AnimationController;

    await tester.pump(const Duration(seconds: 1));
    // Not awaited: a push completes on its pop.
    unawaited(routes.push('/booking'));
    // Frames, as a real screen draws them, through the page's transition.
    for (var i = 0; i < 40; i++) {
      await tester.pump(OpenTimeline.frame);
    }
    final frozenAt = covered().value;
    expect(frozenAt, lessThan(1), reason: 'covered mid-pass');

    // Frames keep coming — a second's worth, read while the splash is still
    // there to read; then longer than the whole pass and its rest.
    Future<void> framesFor(Duration span) async {
      for (var t = Duration.zero; t < span; t += justUnder) {
        await tester.pump(justUnder);
      }
    }

    await framesFor(const Duration(seconds: 1));
    expect(
      covered().value,
      frozenAt,
      reason: 'the covered splash ticked on — its ticker was not muted',
    );
    await framesFor(timeline.firstPass + rest + const Duration(seconds: 1));
    expect(
      home,
      findsNothing,
      reason: 'the splash went /home under the page that covers it',
    );
    expect(booking, findsOneWidget);
    expect(covered().value, frozenAt, reason: 'still frozen');

    // « Retour »: the first frame back draws where the pass would be by now —
    // the end frame — and the finished mark rests before /home.
    routes.pop();
    await tester.pump();
    await tester.pump();
    expect(covered().value, 1, reason: 'the end frame, drawn on return');
    expect(home, findsNothing, reason: 'resting on the finished mark');

    await tester.pump(rest + justUnder);
    await land(tester);
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('a screen reader hears « MyWeli »', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSplash(tester);
    expect(find.bySemanticsLabel(SplashScreen.semanticsLabel), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an asset that will not load never strands the user', (
    tester,
  ) async {
    // The cache keys on the asset name, not the bundle that served it.
    Lottie.cache.clear();
    await pumpSplash(tester, bundle: _MissingAssetBundle());
    await tester.pump();
    expect(
      find.byType(SvgPicture),
      findsOneWidget,
      reason: 'the still brand mark stands in for the animation',
    );
    expect(home, findsNothing, reason: 'held for a rest, not flashed');

    await tester.pump(rest + justUnder);
    await land(tester);
    expect(
      find.text('accueil'),
      findsOneWidget,
      reason: 'a short, bounded hold — then the app',
    );
  });
}

/// A bundle where the consumer animation is missing — a broken build.
class _MissingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == SplashScreen.asset) throw FlutterError('missing: $key');
    return rootBundle.load(key);
  }
}
