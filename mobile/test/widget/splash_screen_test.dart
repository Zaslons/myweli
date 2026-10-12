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
    ],
  );

  Future<void> pumpSplash(WidgetTester tester, {AssetBundle? bundle}) async {
    Widget app = wrapApp(routerConfig: router());
    if (bundle != null) app = DefaultAssetBundle(bundle: bundle, child: app);
    await tester.pumpWidget(app);
    // The composition is decoded off a real bundle read.
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

    await tester.pump(rest - justUnder);
    expect(home, findsNothing, reason: 'the finished mark is still resting');

    await tester.pump(justUnder * 2);
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
